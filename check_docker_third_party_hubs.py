import argparse
import json
import re
import ssl
import sys
import time
from dataclasses import dataclass
from typing import Iterable
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urljoin, urlparse
from urllib.request import Request, urlopen


DEFAULT_JSON_PATH = "accelerating-docker-hub.json"
DEFAULT_TIMEOUT = 10
DEFAULT_IMAGE = "testcontainers/helloworld"
DEFAULT_TAG = "latest"
URL_KEYS = ("registry-mirrors", "docker-hubs")
MANIFEST_ACCEPT_HEADER = (
    "application/vnd.oci.image.index.v1+json,"
    "application/vnd.oci.image.manifest.v1+json,"
    "application/vnd.docker.distribution.manifest.list.v2+json,"
    "application/vnd.docker.distribution.manifest.v2+json,"
    "application/json"
)


@dataclass
class CheckResult:
    url: str
    endpoint: str | None
    is_valid: bool
    status_code: int | None
    response_time: float | None
    message: str


def load_urls(json_path: str) -> list[str]:
    with open(json_path, "r", encoding="utf-8") as file:
        data = json.load(file)

    urls = []
    for key in URL_KEYS:
        values = data.get(key, [])
        if values and not isinstance(values, list):
            raise ValueError(f"{json_path} field '{key}' must be a list")
        urls.extend(values)

    insecure_registries = data.get("insecure-registries", [])
    if insecure_registries and not isinstance(insecure_registries, list):
        raise ValueError(f"{json_path} field 'insecure-registries' must be a list")

    urls.extend(
        registry if "://" in registry else f"http://{registry}"
        for registry in insecure_registries
    )

    if not urls:
        expected_keys = "', '".join((*URL_KEYS, "insecure-registries"))
        raise ValueError(f"{json_path} must contain at least one of '{expected_keys}'")

    invalid_items = [item for item in urls if not isinstance(item, str) or not item.strip()]
    if invalid_items:
        raise ValueError("URL lists must contain only non-empty strings")

    return list(dict.fromkeys(url.strip() for url in urls))


def normalize_url(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("URL must include http:// or https:// and a host")
    return url.rstrip("/") + "/"


def build_manifest_endpoint(url: str, image: str, tag: str) -> str:
    base_url = normalize_url(url)
    api_base_url = base_url if base_url.rstrip("/").endswith("/v2") else urljoin(base_url, "v2/")
    repository = "/".join(quote(part, safe="") for part in image.strip("/").split("/"))
    reference = quote(tag, safe="")
    return urljoin(api_base_url, f"{repository}/manifests/{reference}")


def parse_bearer_challenge(header_value: str | None) -> dict[str, str] | None:
    if not header_value or not header_value.lower().startswith("bearer "):
        return None

    return {
        match.group("key"): match.group("value")
        for match in re.finditer(r'(?P<key>[a-zA-Z_]+)="(?P<value>[^"]*)"', header_value)
    }


def fetch_bearer_token(challenge: dict[str, str], timeout: int) -> str | None:
    realm = challenge.get("realm")
    if not realm:
        return None

    query = {
        key: value
        for key, value in {
            "service": challenge.get("service"),
            "scope": challenge.get("scope"),
        }.items()
        if value
    }
    token_url = realm
    if query:
        separator = "&" if "?" in token_url else "?"
        token_url = f"{token_url}{separator}{urlencode(query)}"

    request = Request(
        token_url,
        method="GET",
        headers={
            "User-Agent": "quick-install-hub-url-checker/1.0",
            "Accept": "application/json",
        },
    )
    with urlopen(request, timeout=timeout, context=ssl.create_default_context()) as response:
        payload = json.loads(response.read().decode("utf-8"))

    token = payload.get("token") or payload.get("access_token")
    return token if isinstance(token, str) and token else None


def request_manifest(endpoint: str, timeout: int, token: str | None = None) -> tuple[int, HTTPError | None]:
    headers = {
        "User-Agent": "quick-install-hub-url-checker/1.0",
        "Accept": MANIFEST_ACCEPT_HEADER,
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    request = Request(endpoint, method="GET", headers=headers)
    try:
        with urlopen(request, timeout=timeout, context=ssl.create_default_context()) as response:
            return response.status, None
    except HTTPError as error:
        return error.code, error


def check_image_pull(url: str, image: str, tag: str, timeout: int) -> CheckResult:
    start_time = time.time()
    endpoint = None

    try:
        endpoint = build_manifest_endpoint(url, image, tag)
        status_code, http_error = request_manifest(endpoint, timeout)
        used_token = False

        if status_code == 401 and http_error is not None:
            challenge = parse_bearer_challenge(http_error.headers.get("WWW-Authenticate"))
            token = fetch_bearer_token(challenge, timeout) if challenge else None
            if token:
                status_code, http_error = request_manifest(endpoint, timeout, token)
                used_token = True

        response_time = round(time.time() - start_time, 3)
        if status_code == 200:
            auth_note = " after bearer token auth" if used_token else ""
            return CheckResult(
                url=url,
                endpoint=endpoint,
                is_valid=True,
                status_code=status_code,
                response_time=response_time,
                message=f"Can fetch manifest for {image}:{tag}{auth_note}",
            )

        return CheckResult(
            url=url,
            endpoint=endpoint,
            is_valid=False,
            status_code=status_code,
            response_time=response_time,
            message=f"Cannot fetch manifest for {image}:{tag}; status code: {status_code}",
        )
    except ValueError as error:
        return CheckResult(
            url=url,
            endpoint=None,
            is_valid=False,
            status_code=None,
            response_time=None,
            message=str(error),
        )
    except TimeoutError:
        return CheckResult(
            url=url,
            endpoint=endpoint,
            is_valid=False,
            status_code=None,
            response_time=round(time.time() - start_time, 3),
            message="Request timed out",
        )
    except URLError as error:
        return CheckResult(
            url=url,
            endpoint=endpoint,
            is_valid=False,
            status_code=None,
            response_time=round(time.time() - start_time, 3),
            message=f"Connection failed: {error.reason}",
        )
    except Exception as error:
        return CheckResult(
            url=url,
            endpoint=endpoint,
            is_valid=False,
            status_code=None,
            response_time=round(time.time() - start_time, 3),
            message=f"Check failed: {error}",
        )


def print_results(results: Iterable[CheckResult]) -> None:
    for result in results:
        status = "VALID" if result.is_valid else "INVALID"
        status_code = result.status_code if result.status_code is not None else "-"
        response_time = f"{result.response_time}s" if result.response_time is not None else "-"
        print(f"[{status}] {result.url}")
        print(f"  endpoint: {result.endpoint or '-'}")
        print(f"  status:   {status_code}")
        print(f"  time:     {response_time}")
        print(f"  message:  {result.message}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check whether Docker Hub acceleration mirrors can fetch a test image manifest."
    )
    parser.add_argument(
        "json_path",
        nargs="?",
        default=DEFAULT_JSON_PATH,
        help=f"Path to JSON file. Defaults to {DEFAULT_JSON_PATH}.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT,
        help=f"Request timeout in seconds. Defaults to {DEFAULT_TIMEOUT}.",
    )
    parser.add_argument(
        "--image",
        default=DEFAULT_IMAGE,
        help=f"Image repository to check. Defaults to {DEFAULT_IMAGE}.",
    )
    parser.add_argument(
        "--tag",
        default=DEFAULT_TAG,
        help=f"Image tag to check. Defaults to {DEFAULT_TAG}.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        urls = load_urls(args.json_path)
    except Exception as error:
        print(f"Failed to load URLs: {error}", file=sys.stderr)
        return 2

    results = [check_image_pull(url, args.image, args.tag, args.timeout) for url in urls]
    print_results(results)

    valid_count = sum(result.is_valid for result in results)
    print(f"\nSummary: {valid_count}/{len(results)} URLs are valid")
    return 0 if valid_count == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())

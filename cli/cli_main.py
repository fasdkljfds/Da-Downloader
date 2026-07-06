from __future__ import annotations

import argparse
import json
import os
from typing import Iterable

from downloader.wallhaven import (
    DEFAULT_EXTENSIONS,
    DEFAULT_SITE_URL,
    TARGET_SITE_URL,
    DownloadResult,
    WallhavenDownloader,
    print_result,
)


def parse_pages(raw: str) -> list[int]:
    pages = []
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            try:
                start, end = part.split("-", 1)
                start_page = int(start)
                end_page = int(end)
            except ValueError as exc:
                raise argparse.ArgumentTypeError(f"Invalid page range: {part}") from exc
            if end_page < start_page:
                raise argparse.ArgumentTypeError(f"Invalid page range: {part}")
            if start_page < 1:
                raise argparse.ArgumentTypeError("Pages must be >= 1.")
            pages.extend(range(start_page, end_page + 1))
        else:
            try:
                page = int(part)
            except ValueError as exc:
                raise argparse.ArgumentTypeError(f"Invalid page: {part}") from exc
            if page < 1:
                raise argparse.ArgumentTypeError("Pages must be >= 1.")
            pages.append(page)

    if not pages:
        raise argparse.ArgumentTypeError("At least one page is required.")

    return pages


def parse_extensions(raw: str) -> tuple[str, ...]:
    extensions = []
    for ext in raw.split(","):
        ext = ext.strip()
        if not ext:
            continue
        normalized = ext if ext.startswith(".") else f".{ext}"
        extensions.append(normalized.lower())
    return tuple(extensions) or DEFAULT_EXTENSIONS


def positive_int(raw: str) -> int:
    try:
        value = int(raw)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"Invalid integer: {raw}") from exc
    if value < 1:
        raise argparse.ArgumentTypeError("Value must be >= 1.")
    return value


def add_wallhaven_common_args(
    parser: argparse.ArgumentParser,
    site_url_default: str = DEFAULT_SITE_URL,
):
    parser.add_argument(
        "--json",
        dest="json_output",
        action="store_true",
        default=argparse.SUPPRESS,
        help="Print a machine-readable JSON result to stdout.",
    )
    parser.add_argument(
        "--save-dir",
        default=r"F:\estore\wallpaper",
        help="Directory used to save images and history.json.",
    )
    parser.add_argument(
        "--site-url",
        default=site_url_default,
        help="Wallhaven list URL prefix. Use {page} as a placeholder if needed.",
    )
    parser.add_argument(
        "--cookie",
        default="""_pk_id.1.01b8=4ba6e2403d32ff0e.1766719365.; remember_web_59ba36addc2b2f9401580f014c7f58ea4e30989d=eyJpdiI6Im8ycHhnUzlkdnFnS0ZBMVBTa3c0dWc9PSIsInZhbHVlIjoiYWYraTVUZW1GM0VqTU5XUm0rQmxGa1FRcGJPb0JheFJhdFJXUkYxSFM5Mk1Ec1hnMWF5WU5jb0NjSkpacXlMRlIzRCtDc0pGUldIZzIyMTU4N2NpOHhjWUI3M0NUTzZGbGcrYWlKWTZDajY0aDVZQWMrT2lLRGxuZTlFSEZSNUt3VitnT1Y5ZTM0Z1ZQdERcL1NMRGxXdTNNMnJHR3lIblpMR21jeGpXbXF3VVRNWnBFU3IzSlpKemVUdFE2elFIdiIsIm1hYyI6ImMxYTE1NmMwM2JjZjlkYzQ0N2Q2ODhiZjIwNDU1MWJmN2U1YmUzYmIwZjM3MzcyYWJkNDhkM2E3MjRmZTYwZGUifQ%3D%3D; _pk_ref.1.01b8=%5B%22%22%2C%22%22%2C1783350762%2C%22https%3A%2F%2Fwww.google.com%2F%22%5D; _pk_ses.1.01b8=1; cf_clearance=yBqKgLiEs58dehVpTmbXqGPykQBxDAvICNZCXX5_6F4-1783351737-1.2.1.1-BDxadEI99aea1ee9842FMz6jyUWuCcuhth1Qs8nSg_fh1jhx7823c6mCBwv_FXnIpH9x4F0W7Js1Ld8kYHe58CqhyRDjIjSG5nPOzSXRqAEZ5BUBiozyj7Pq7LTeuA67bHtwI4xz44fMZLyrFoq.qj5LNKYz0rv1eV4sdWxWdwC_XyKCnbZKe8VZLMwb7J2x_NZEW9n8_3wdkZV4LlxE8f.EjzPar1iIlMkAP1bjQzm0NLWAQWkzBmVE78lokS9UBesjWkgNY8o5ye93PSg0A3E.To9leXJF_sw9SLQ8mv7Q.5NCFPLZnGhecvH9SPqwF6qfLRpJkTcXpXv3IpwEhNrYqxr5LfdAcakFG_5bTwWFXhvjguD0bbNl2RDzQ4Z9NfanJ3abchATAyd6INNGrxUksO7F592Ry6vko9T7gRXDA7rPKfINxzDKidNpGEiE; XSRF-TOKEN=eyJpdiI6IjMzTTJBWmlkcU53ODVadWZ6R2xMYVE9PSIsInZhbHVlIjoiaXVLNWFEYys3MkhoUzE5Sm9sS09HalhMTTdDUUhhTHN0bnl2WkU2ekFPYlRDZGZSN1NyU2ZuT2M1cGxlRGlGNyIsIm1hYyI6ImUzMzcyYzAxMzNmYzA4MmYzMGJlMmI0YzdmZjU5MDY5ODFiMTgwYTZhYjgyODMzOWQ4MmIyZTBjZmM5N2NiNWIifQ%3D%3D; wallhaven_session=eyJpdiI6IkhGQTJaS2cwVnRcLzFEYlZsN200WFV3PT0iLCJ2YWx1ZSI6IlFkdU50dnhUVE9VdU9aNitUdWxBb0hUNkErOVwvOU5YQUVuejliS043angrSEp1ZHVMcmpSbVROeEl2YktVQ0hkIiwibWFjIjoiYmEyN2QzOTZkOTI2MzM3ZGY4NTY2ZDdlNzllMjk4MzQ4N2IwMjEzM2QzNWIxMmUxNjhkYWE5ZjAxOGNiZGEyZiJ9""",
        help="Wallhaven Cookie value. Prefer WALLHAVEN_COOKIE for private favorites.",
    )
    parser.add_argument(
        "--cookie-env",
        default="WALLHAVEN_COOKIE",
        help="Environment variable name used for the Cookie.",
    )
    parser.add_argument(
        "--referer",
        default=os.environ.get("WALLHAVEN_REFERER"),
        help="Referer header, useful for private favorites.",
    )
    parser.add_argument(
        "--extensions",
        default=",".join(DEFAULT_EXTENSIONS),
        help="Comma-separated file extensions to try, e.g. jpg,png,jpeg.",
    )
    parser.add_argument("--timeout", type=int, default=15, help="Request timeout in seconds.")
    parser.add_argument("--tries", type=int, default=3, help="Max request retries.")
    parser.add_argument("--delay", type=float, default=0, help="Delay between images in seconds.")
    parser.add_argument("--force", action="store_true", help="Download even if history says it exists.")


def create_wallhaven_downloader(args: argparse.Namespace) -> WallhavenDownloader:
    cookie = args.cookie or os.environ.get(args.cookie_env)
    return WallhavenDownloader(
        save_dir=args.save_dir,
        extensions=parse_extensions(args.extensions),
        site_url=args.site_url,
        cookie=cookie,
        referer=args.referer,
        timeout=args.timeout,
        max_tries=args.tries,
        delay=args.delay,
    )


def run_page(args: argparse.Namespace) -> DownloadResult:
    downloader = create_wallhaven_downloader(args)
    return downloader.download_pages(args.pages, force=args.force)


def run_update(args: argparse.Namespace) -> DownloadResult:
    downloader = create_wallhaven_downloader(args)
    return downloader.update(
        start_page=args.start_page,
        max_pages=args.max_pages,
        force=args.force,
        stop_when_known=not args.no_stop_when_known,
    )


def run_image(args: argparse.Namespace) -> DownloadResult:
    downloader = create_wallhaven_downloader(args)
    return downloader.download_image(args.image, force=args.force)


def run_retry(args: argparse.Namespace) -> DownloadResult:
    downloader = create_wallhaven_downloader(args)
    return downloader.retry_failed(force=True)


def run_status(args: argparse.Namespace) -> dict[str, object]:
    downloader = create_wallhaven_downloader(args)
    stats = downloader.history_stats()
    return {
        "save_dir": os.path.abspath(args.save_dir),
        "downloaded": stats["downloaded"],
        "failed": stats["failed"],
    }


def print_status(status: dict[str, object]):
    print(f"Save directory: {status['save_dir']}")
    print(f"Downloaded: {status['downloaded']}")
    print(f"Failed: {status['failed']}")


def payload_to_jsonable(payload):
    if isinstance(payload, DownloadResult):
        return payload.to_dict()
    return payload


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="library-cli",
        description="Personal media library downloader.",
    )
    parser.add_argument(
        "--json",
        dest="json_output",
        action="store_true",
        help="Print a machine-readable JSON result to stdout.",
    )
    subparsers = parser.add_subparsers(dest="source", required=True)

    wallhaven = subparsers.add_parser("wallhaven", help="Download images from Wallhaven.")
    wallhaven_subparsers = wallhaven.add_subparsers(dest="action", required=True)

    page_parser = wallhaven_subparsers.add_parser(
        "page",
        help="Download one or more list pages. Example: wallhaven page 1-3,8",
    )
    add_wallhaven_common_args(page_parser)
    page_parser.add_argument("pages", type=parse_pages, help="Pages like 1,2,5 or 1-5.")
    page_parser.set_defaults(func=run_page)

    update_parser = wallhaven_subparsers.add_parser(
        "update",
        help="Update from the target Wallhaven favorites collection until existing images are reached.",
    )
    add_wallhaven_common_args(update_parser, site_url_default=TARGET_SITE_URL)
    update_parser.add_argument("--start-page", type=positive_int, default=1, help="First page to check.")
    update_parser.add_argument("--max-pages", type=positive_int, default=None, help="Maximum pages to check.")
    update_parser.add_argument(
        "--no-stop-when-known",
        action="store_true",
        help="Keep checking pages even after a fully known page is reached.",
    )
    update_parser.set_defaults(func=run_update)

    image_parser = wallhaven_subparsers.add_parser(
        "image",
        help="Download a single image id or URL.",
    )
    add_wallhaven_common_args(image_parser)
    image_parser.add_argument("image", help="Image id, image URL, or wallhaven page URL.")
    image_parser.set_defaults(func=run_image)

    retry_parser = wallhaven_subparsers.add_parser(
        "retry",
        help="Retry images recorded in history.json as failed.",
    )
    add_wallhaven_common_args(retry_parser)
    retry_parser.set_defaults(func=run_retry)

    status_parser = wallhaven_subparsers.add_parser(
        "status",
        help="Show local download history stats.",
    )
    add_wallhaven_common_args(status_parser)
    status_parser.set_defaults(func=run_status)

    return parser


def main(argv: Iterable[str] | None = None):
    parser = build_parser()
    args = parser.parse_args(argv)
    payload = args.func(args)

    if getattr(args, "json_output", False):
        print(json.dumps(payload_to_jsonable(payload), ensure_ascii=False))
    elif isinstance(payload, DownloadResult):
        print_result(payload)
    else:
        print_status(payload)
    

if __name__ == "__main__":
    main()

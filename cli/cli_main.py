import argparse
import os
from typing import Iterable

from downloader.wallhaven import (
    DEFAULT_EXTENSIONS,
    DEFAULT_SITE_URL,
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
            start, end = part.split("-", 1)
            start_page = int(start)
            end_page = int(end)
            if end_page < start_page:
                raise argparse.ArgumentTypeError(f"Invalid page range: {part}")
            pages.extend(range(start_page, end_page + 1))
        else:
            pages.append(int(part))

    if not pages:
        raise argparse.ArgumentTypeError("At least one page is required.")

    return pages


def parse_extensions(raw: str) -> tuple[str, ...]:
    extensions = []
    for ext in raw.split(","):
        ext = ext.strip()
        if not ext:
            continue
        extensions.append(ext if ext.startswith(".") else f".{ext}")
    return tuple(extensions) or DEFAULT_EXTENSIONS


def add_wallhaven_common_args(parser: argparse.ArgumentParser):
    parser.add_argument(
        "--save-dir",
        default=os.path.join("libraries", "wallhaven"),
        help="Directory used to save images and history.json.",
    )
    parser.add_argument(
        "--site-url",
        default=DEFAULT_SITE_URL,
        help="Wallhaven list URL prefix. Use {page} as a placeholder if needed.",
    )
    parser.add_argument(
        "--cookie",
        default=None,
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


def run_page(args: argparse.Namespace):
    downloader = create_wallhaven_downloader(args)
    result = downloader.download_pages(args.pages, force=args.force)
    print_result(result)


def run_image(args: argparse.Namespace):
    downloader = create_wallhaven_downloader(args)
    result = downloader.download_image(args.image, force=args.force)
    print_result(result)


def run_retry(args: argparse.Namespace):
    downloader = create_wallhaven_downloader(args)
    result = downloader.retry_failed(force=True)
    print_result(result)


def run_status(args: argparse.Namespace):
    downloader = create_wallhaven_downloader(args)
    stats = downloader.history_stats()
    print(f"Save directory: {os.path.abspath(args.save_dir)}")
    print(f"Downloaded: {stats['downloaded']}")
    print(f"Failed: {stats['failed']}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="library-cli",
        description="Personal media library downloader.",
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
    args.func(args)


if __name__ == "__main__":
    main()

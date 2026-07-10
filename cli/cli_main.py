from __future__ import annotations

import argparse
import json
from typing import Iterable

from cli.wallhaven_cli import (
    add_wallhaven_common_args,
    add_wallhaven_parser,
    create_wallhaven_downloader,
    parse_extensions,
    parse_pages,
    positive_int,
    print_status,
    run_image,
    run_page,
    run_retry,
    run_status,
    run_update,
)
from cli.youtube_cli import add_youtube_parser
from downloader.wallhaven import DownloadResult, WallhavenDownloader, print_result
from downloader.youtube import YoutubeDownloadResult, YoutubeDownloader, print_youtube_result


def payload_to_jsonable(payload):
    if hasattr(payload, "to_dict"):
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
    add_wallhaven_parser(subparsers)
    add_youtube_parser(subparsers)
    return parser


def main(argv: Iterable[str] | None = None):
    parser = build_parser()
    args = parser.parse_args(argv)
    payload = args.func(args)

    if getattr(args, "json_output", False):
        print(json.dumps(payload_to_jsonable(payload), ensure_ascii=False))
        return payload

    printer = getattr(args, "printer", None)
    if printer:
        printer(payload)
    else:
        print(payload)
    return payload


if __name__ == "__main__":
    main()

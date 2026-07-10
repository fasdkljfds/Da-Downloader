from __future__ import annotations

import argparse

from downloader.youtube import (
    DEFAULT_FORMAT_SELECTOR,
    DEFAULT_OUTPUT_TEMPLATE,
    DEFAULT_SAVE_DIR,
    YoutubeDownloadResult,
    YoutubeDownloader,
    print_youtube_result,
)


def resolve_youtube_url(target: list[str]) -> str:
    if len(target) == 1:
        return target[0]
    if len(target) == 2 and target[0].lower() in {"download", "dl"}:
        return target[1]
    raise ValueError("Use either: youtube URL, or: youtube download URL")


def create_youtube_downloader(args: argparse.Namespace) -> YoutubeDownloader:
    return YoutubeDownloader(
        save_dir=args.save_dir,
        output_template=args.output_template,
        format_selector=args.format_selector,
        merge_output_format=args.merge_output_format,
        cookies=args.cookies,
        cookies_from_browser=args.cookies_from_browser,
        no_playlist=not args.playlist,
        executable=args.executable,
        embed_metadata=args.embed_metadata,
        write_thumbnail=args.write_thumbnail,
        restrict_filenames=args.restrict_filenames,
        extra_args=args.extra_arg,
    )


def run_download(args: argparse.Namespace) -> YoutubeDownloadResult:
    downloader = create_youtube_downloader(args)
    return downloader.download(
        resolve_youtube_url(args.target),
        echo_output=not getattr(args, "json_output", False),
    )


def add_youtube_parser(subparsers) -> argparse.ArgumentParser:
    youtube = subparsers.add_parser(
        "youtube",
        aliases=["yt"],
        help="Download videos from YouTube with yt-dlp.",
    )
    youtube.add_argument(
        "--json",
        dest="json_output",
        action="store_true",
        default=argparse.SUPPRESS,
        help="Print a machine-readable JSON result to stdout.",
    )
    youtube.add_argument(
        "--save-dir",
        default=DEFAULT_SAVE_DIR,
        help="Directory used to save downloaded videos.",
    )
    youtube.add_argument(
        "--format",
        dest="format_selector",
        default=DEFAULT_FORMAT_SELECTOR,
        help="yt-dlp format selector. Default chooses best video plus best audio.",
    )
    youtube.add_argument(
        "--output-template",
        default=DEFAULT_OUTPUT_TEMPLATE,
        help="yt-dlp output template relative to --save-dir.",
    )
    youtube.add_argument(
        "--merge-output-format",
        default=None,
        help="Optional merge container, for example mp4 or mkv.",
    )
    youtube.add_argument(
        "--cookies",
        default=None,
        help="Path to a Netscape cookies.txt file for yt-dlp.",
    )
    youtube.add_argument(
        "--cookies-from-browser",
        default=None,
        help='Browser cookies source for yt-dlp, for example "chrome" or "firefox".',
    )
    youtube.add_argument(
        "--playlist",
        action="store_true",
        help="Allow playlist downloads. By default only the single video is downloaded.",
    )
    youtube.add_argument(
        "--yt-dlp",
        dest="executable",
        default=None,
        help="Explicit yt-dlp executable path.",
    )
    youtube.add_argument(
        "--embed-metadata",
        action="store_true",
        help="Ask yt-dlp to embed metadata when supported.",
    )
    youtube.add_argument(
        "--write-thumbnail",
        action="store_true",
        help="Ask yt-dlp to save the thumbnail.",
    )
    youtube.add_argument(
        "--restrict-filenames",
        action="store_true",
        help="Restrict filenames to ASCII characters.",
    )
    youtube.add_argument(
        "--extra-arg",
        action="append",
        default=[],
        help="Pass one raw extra argument to yt-dlp. Repeat as needed.",
    )
    youtube.add_argument(
        "target",
        nargs="+",
        metavar="URL",
        help="YouTube URL. Also accepts: youtube download URL.",
    )
    youtube.set_defaults(func=run_download, printer=print_youtube_result)
    return youtube

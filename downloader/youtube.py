from __future__ import annotations

import importlib.util
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Iterable


DEFAULT_SAVE_DIR = os.path.join("libraries", "youtube")
DEFAULT_OUTPUT_TEMPLATE = "%(title).200B [%(id)s].%(ext)s"
DEFAULT_FORMAT_SELECTOR = "bv*+ba/b"


def _looks_like_downloaded_path(line: str) -> bool:
    value = line.strip()
    if not value or value.startswith("[") or value.startswith(("WARNING:", "ERROR:")):
        return False
    return os.path.isabs(value) or os.path.exists(value)


@dataclass
class YoutubeDownloadResult:
    requested: int = 0
    downloaded: int = 0
    failed: int = 0
    files: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    url: str = ""
    returncode: int | None = None

    def to_dict(self) -> dict[str, object]:
        return {
            "requested": self.requested,
            "downloaded": self.downloaded,
            "failed": self.failed,
            "files": list(self.files),
            "errors": list(self.errors),
            "url": self.url,
            "returncode": self.returncode,
        }


class YoutubeDownloader:
    def __init__(
        self,
        save_dir: str = DEFAULT_SAVE_DIR,
        output_template: str = DEFAULT_OUTPUT_TEMPLATE,
        format_selector: str = DEFAULT_FORMAT_SELECTOR,
        merge_output_format: str | None = None,
        cookies: str | None = None,
        cookies_from_browser: str | None = None,
        no_playlist: bool = True,
        executable: str | None = None,
        embed_metadata: bool = False,
        write_thumbnail: bool = False,
        restrict_filenames: bool = False,
        extra_args: Iterable[str] | None = None,
    ):
        self.save_dir = os.path.abspath(save_dir)
        self.output_template = output_template
        self.format_selector = format_selector
        self.merge_output_format = merge_output_format
        self.cookies = cookies
        self.cookies_from_browser = cookies_from_browser
        self.no_playlist = no_playlist
        self.executable = executable
        self.embed_metadata = embed_metadata
        self.write_thumbnail = write_thumbnail
        self.restrict_filenames = restrict_filenames
        self.extra_args = list(extra_args or [])

    def _base_command(self) -> list[str]:
        if self.executable:
            return [self.executable]

        yt_dlp = shutil.which("yt-dlp")
        if yt_dlp:
            return [yt_dlp]

        if importlib.util.find_spec("yt_dlp"):
            return [sys.executable, "-m", "yt_dlp"]

        raise RuntimeError("yt-dlp is required. Install it with: py -m pip install yt-dlp")

    def build_command(self, url: str) -> list[str]:
        url = url.strip()
        if not url:
            raise ValueError("YouTube URL cannot be empty.")

        command = self._base_command()
        command.extend(
            [
                "--format",
                self.format_selector,
                "--paths",
                self.save_dir,
                "--output",
                self.output_template,
                "--no-simulate",
                "--print",
                "after_move:filepath",
                "--progress",
                "--newline",
            ]
        )

        if self.no_playlist:
            command.append("--no-playlist")
        if self.merge_output_format:
            command.extend(["--merge-output-format", self.merge_output_format])
        if self.cookies:
            command.extend(["--cookies", self.cookies])
        if self.cookies_from_browser:
            command.extend(["--cookies-from-browser", self.cookies_from_browser])
        if self.embed_metadata:
            command.append("--embed-metadata")
        if self.write_thumbnail:
            command.append("--write-thumbnail")
        if self.restrict_filenames:
            command.append("--restrict-filenames")

        command.extend(self.extra_args)
        command.append(url)
        return command

    def download(self, url: str, echo_output: bool = False) -> YoutubeDownloadResult:
        result = YoutubeDownloadResult(requested=1, url=url)
        try:
            command = self.build_command(url)
        except (RuntimeError, ValueError) as exc:
            result.failed = 1
            result.errors.append(str(exc))
            return result

        os.makedirs(self.save_dir, exist_ok=True)
        try:
            process = subprocess.Popen(
                command,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                bufsize=1,
            )
        except OSError as exc:
            result.failed = 1
            result.errors.append(str(exc))
            return result
        output_lines = []
        if process.stdout:
            for line in process.stdout:
                output_lines.append(line)
                if echo_output:
                    print(line, end="", file=sys.stderr)

        result.returncode = process.wait()
        output = "".join(output_lines)
        files = [
            line.strip()
            for line in output.splitlines()
            if _looks_like_downloaded_path(line)
        ]
        result.files.extend(files)

        if result.returncode == 0:
            result.downloaded = 1
        else:
            result.failed = 1
            result.errors.append(output.strip() or f"yt-dlp exited with code {result.returncode}")

        return result


def print_youtube_result(result: YoutubeDownloadResult, stream=None):
    stream = stream or sys.stdout
    print(
        "Done: "
        f"requested={result.requested}, "
        f"downloaded={result.downloaded}, "
        f"failed={result.failed}",
        file=stream,
    )
    for path in result.files:
        print(path, file=stream)
    for error in result.errors:
        print(error, file=stream)

# 核心调用链
# update / download_pages
#         ↓
# get_page_image_ids(page)
#         ↓
# download_image_ids(image_ids)
#         ↓
# download_image(image_id)
#         ↓
# _download(image_url, save_path)


from __future__ import annotations


import os
import re
import sys
import time
from dataclasses import dataclass, field
from typing import Iterable
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

try:
    from tqdm import tqdm
except ImportError:
    tqdm = None

from infra.context_manager import ContextManager


DEFAULT_SITE_URL = "https://wallhaven.cc/favorites?page="
TARGET_SITE_URL = "https://wallhaven.cc/user/sjjfirk/favorites/2119257?purity=110&page="
DEFAULT_EXTENSIONS = (".jpg", ".png", ".jpeg")
DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0"
)


@dataclass
class DownloadResult:
    requested: int = 0
    downloaded: int = 0
    skipped: int = 0
    failed: int = 0
    files: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def add(self, other: "DownloadResult"):
        self.requested += other.requested
        self.downloaded += other.downloaded
        self.skipped += other.skipped
        self.failed += other.failed
        self.files.extend(other.files)
        self.errors.extend(other.errors)
        return self

    def to_dict(self) -> dict[str, object]:
        return {
            "requested": self.requested,
            "downloaded": self.downloaded,
            "skipped": self.skipped,
            "failed": self.failed,
            "files": list(self.files),
            "errors": list(self.errors),
        }


class WallhavenDownloader:
    def __init__(
        self,
        save_dir: str,
        extensions: Iterable[str] | None = None,
        site_url: str = DEFAULT_SITE_URL,
        cookie: str | None = None,
        referer: str | None = None,
        timeout: int = 15,
        max_tries: int = 3,
        delay: float = 0,
        history_file: str | None = None,
        **legacy_kwargs,
    ):
        self.extensions = tuple(extensions or legacy_kwargs.get("EXTENSIONS") or DEFAULT_EXTENSIONS)
        self.site_url = legacy_kwargs.get("SITE_URL", site_url)
        self.cookie = legacy_kwargs.get("COOKIE", cookie)
        self.referer = legacy_kwargs.get("REFERER", referer)
        self.timeout = timeout
        self.max_tries = max_tries
        self.delay = delay

        self.save_dir = os.path.abspath(save_dir)
        os.makedirs(self.save_dir, exist_ok=True)

        self.cm = ContextManager(history_file=history_file or os.path.join(self.save_dir, "history.json"))

    def _log(self, message: str):
        print(message, file=sys.stderr)

    def _headers(self) -> dict[str, str]:
        headers = {"User-Agent": DEFAULT_USER_AGENT}
        if self.cookie:
            headers["Cookie"] = self.cookie
        if self.referer:
            headers["Referer"] = self.referer
        return headers

    def _request(self, url: str):
        last_error = None
        for attempt in range(1, self.max_tries + 1):
            try:
                request = Request(url, headers=self._headers())
                return urlopen(request, timeout=self.timeout)
            except (HTTPError, URLError, TimeoutError) as exc:
                if isinstance(exc, HTTPError):
                    return exc
                last_error = exc
                if attempt < self.max_tries:
                    self._log(f"Request failed, retrying {attempt}/{self.max_tries}: {exc}")
                    time.sleep(min(attempt, 5))

        self._log(f"Request failed after {self.max_tries} tries: {last_error}")
        return None

    def _page_url(self, page: int) -> str:
        if page < 1:
            raise ValueError("page must be >= 1.")
        if "{page}" in self.site_url:
            return self.site_url.format(page=page)
        if self.site_url.endswith(("=", "/", "?", "&")):
            return f"{self.site_url}{page}"
        separator = "&page=" if urlparse(self.site_url).query else "?page="
        return f"{self.site_url}{separator}{page}"

    def _download(self, image_url: str, save_path: str) -> bool:
        response = self._request(url=image_url)
        if not response:
            return False

        temp_path = f"{save_path}.part"
        bar = None
        downloaded = False

        try:
            status = getattr(response, "status", None) or getattr(response, "code", None)
            if status != 200:
                return False

            content_type = response.headers.get("content-type", "")
            if content_type and "image" not in content_type.lower():
                return False

            try:
                total = int(response.headers.get("content-length", 0))
            except ValueError:
                total = 0

            if tqdm:
                bar = tqdm(
                    total=total or None,
                    unit="B",
                    unit_scale=True,
                    unit_divisor=1024,
                    desc=os.path.basename(save_path),
                    file=sys.stderr,
                )

            with open(temp_path, "wb") as f:
                while True:
                    chunk = response.read(1024 * 64)
                    if not chunk:
                        break
                    f.write(chunk)
                    if bar:
                        bar.update(len(chunk))
            os.replace(temp_path, save_path)
            downloaded = True
            return True
        except OSError as exc:
            self._log(f"File write failed: {save_path}: {exc}")
            return False
        finally:
            if bar:
                bar.close()
            close = getattr(response, "close", None)
            if close:
                close()
            if not downloaded and os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except OSError:
                    pass
    
    @staticmethod
    def normalize_image_id(image: str) -> str:
        image = image.strip()
        if not image:
            raise ValueError("Image id cannot be empty.")

        patterns = [
            r"wallhaven-([A-Za-z0-9]+)(?:\.[A-Za-z0-9]+)?$",
            r"/w/([A-Za-z0-9]+)",
            r"^([A-Za-z0-9]+)$",
        ]
        for pattern in patterns:
            match = re.search(pattern, image)
            if match:
                return match.group(1)

        parsed = urlparse(image)
        if parsed.path:
            name = os.path.basename(parsed.path)
            match = re.search(r"([A-Za-z0-9]+)", name)
            if match:
                return match.group(1)

        raise ValueError(f"Cannot parse wallhaven image id from: {image}")

    @staticmethod
    def base_url_for(image_id: str) -> str:
        return f"https://w.wallhaven.cc/full/{image_id[:2]}/wallhaven-{image_id}"

    def _image_exists_locally(self, image_id: str) -> bool:
        return any(
            os.path.exists(os.path.join(self.save_dir, f"{image_id}{ext}"))
            for ext in self.extensions
        )

    def _image_known(self, image_id: str) -> bool:
        return self.cm.exist(self.base_url_for(image_id)) or self._image_exists_locally(image_id)

    def download_image(self, image: str, force: bool = False) -> DownloadResult:
        image_id = self.normalize_image_id(image)
        base_url = self.base_url_for(image_id)
        result = DownloadResult(requested=1)

        if self.cm.exist(base_url) and not force:
            self._log(f"Skip existing image: {image_id}")
            result.skipped = 1
            return result

        self._log(f"Download image: {image_id}")
        for ext in self.extensions:
            filename = f"{image_id}{ext}"
            save_path = os.path.join(self.save_dir, filename)
            url = f"{base_url}{ext}"

            if os.path.exists(save_path) and not force:
                self.cm.mark_downloaded(base_url)
                result.skipped = 1
                result.files.append(save_path)
                return result

            if self._download(image_url=url, save_path=save_path):
                self.cm.mark_downloaded(base_url)
                result.downloaded = 1
                result.files.append(save_path)
                return result

        self.cm.mark_error(base_url)
        result.failed = 1
        result.errors.append(image_id)
        return result

    def _download_single_image(self, image_name: str) -> bool:
        result = self.download_image(image_name)
        return result.downloaded > 0 or result.skipped > 0

    def download_image_ids(self, image_ids: Iterable[str], force: bool = False) -> DownloadResult:
        result = DownloadResult()
        for image_id in image_ids:
            result.add(self.download_image(image_id, force=force))
            if self.delay > 0:
                time.sleep(self.delay)
        return result

    def get_page_image_ids(self, page: int) -> list[str]:
        url = self._page_url(page)
        response = self._request(url=url)
        if not response:
            return []
        try:
            status = getattr(response, "status", None) or getattr(response, "code", None)
            if status != 200:
                self._log(f"Page request failed: HTTP {status} {url}")
                return []

            raw = response.read()
            text = raw.decode("utf-8", errors="ignore")
        finally:
            close = getattr(response, "close", None)
            if close:
                close()

        patterns = [
            r"(?:https?:)?//th\.wallhaven\.cc/small/[^/]+/wallhaven-([A-Za-z0-9]+)\.",
            r"(?:https?:)?//wallhaven\.cc/w/([A-Za-z0-9]+)",
            r"/w/([A-Za-z0-9]+)",
        ]
        seen = set()
        ids = []
        for pattern in patterns:
            for image_id in re.findall(pattern, text):
                if image_id not in seen:
                    seen.add(image_id)
                    ids.append(image_id)
        return ids

    def download_page(self, page: int, force: bool = False) -> DownloadResult:
        
        image_ids = self.get_page_image_ids(page=page)
        self._log(f"Page {page}: found {len(image_ids)} images")
        return self.download_image_ids(image_ids, force=force)

    def update(
        self,
        start_page: int = 1,
        max_pages: int | None = None,
        force: bool = False,
        stop_when_known: bool = True,
    ) -> DownloadResult:
        if start_page < 1:
            raise ValueError("start_page must be >= 1.")
        if max_pages is not None and max_pages < 1:
            raise ValueError("max_pages must be >= 1.")

        result = DownloadResult()
        page = start_page
        checked_pages = 0

        while max_pages is None or checked_pages < max_pages:
            image_ids = self.get_page_image_ids(page=page)
            if not image_ids:
                self._log(f"Page {page}: no images found, stop update")
                break

            known_count = sum(1 for image_id in image_ids if self._image_known(image_id))
            self._log(f"Page {page}: found {len(image_ids)} images, known={known_count}")

            if stop_when_known and not force and known_count == len(image_ids):
                self._log(f"Page {page}: all images are already known, stop update")
                break

            page_result = self.download_image_ids(image_ids, force=force)
            result.add(page_result)
            checked_pages += 1

            if (
                stop_when_known
                and not force
                and page_result.downloaded == 0
                and page_result.failed == 0
                and page_result.skipped == page_result.requested
                and page_result.requested > 0
            ):
                self._log(f"Page {page}: no new images, stop update")
                break

            page += 1

        return result

    def download_pages(self, pages: Iterable[int], force: bool = False) -> DownloadResult:
        result = DownloadResult()
        for page in pages:
            if page < 1:
                raise ValueError("page must be >= 1.")
            result.add(self.download_page(page, force=force))
        return result

    def retry_failed(self, force: bool = True) -> DownloadResult:
        failed = list(self.cm.failed())
        result = DownloadResult()
        self._log(f"Retry failed images: {len(failed)}")

        for url in failed:
            try:
                image_id = self.normalize_image_id(url)
            except ValueError:
                result.failed += 1
                result.errors.append(url)
                continue
            item_result = self.download_image(image_id, force=force)
            result.add(item_result)
            if item_result.downloaded:
                self.cm.clear_error(url)

        return result

    def history_stats(self) -> dict[str, int]:
        return self.cm.stats()


def print_result(result: DownloadResult, stream=None):
    stream = stream or sys.stdout
    print(
        "Done: "
        f"requested={result.requested}, "
        f"downloaded={result.downloaded}, "
        f"skipped={result.skipped}, "
        f"failed={result.failed}",
        file=stream,
    )



MAIN_PAGES = (1, 2, 3, 4, 5)


def create_default_downloader() -> WallhavenDownloader:
    return WallhavenDownloader(
        save_dir=r"F:\estore\wallpaper",
        extensions=(".jpg", ".png", ".jpeg"),
        site_url="https://wallhaven.cc/user/sjjfirk/favorites/2119257?purity=001&page=",
        cookie="""_pk_id.1.01b8=4ba6e2403d32ff0e.1766719365.; remember_web_59ba36addc2b2f9401580f014c7f58ea4e30989d=eyJpdiI6Im8ycHhnUzlkdnFnS0ZBMVBTa3c0dWc9PSIsInZhbHVlIjoiYWYraTVUZW1GM0VqTU5XUm0rQmxGa1FRcGJPb0JheFJhdFJXUkYxSFM5Mk1Ec1hnMWF5WU5jb0NjSkpacXlMRlIzRCtDc0pGUldIZzIyMTU4N2NpOHhjWUI3M0NUTzZGbGcrYWlKWTZDajY0aDVZQWMrT2lLRGxuZTlFSEZSNUt3VitnT1Y5ZTM0Z1ZQdERcL1NMRGxXdTNNMnJHR3lIblpMR21jeGpXbXF3VVRNWnBFU3IzSlpKemVUdFE2elFIdiIsIm1hYyI6ImMxYTE1NmMwM2JjZjlkYzQ0N2Q2ODhiZjIwNDU1MWJmN2U1YmUzYmIwZjM3MzcyYWJkNDhkM2E3MjRmZTYwZGUifQ%3D%3D; _pk_ref.1.01b8=%5B%22%22%2C%22%22%2C1783350762%2C%22https%3A%2F%2Fwww.google.com%2F%22%5D; _pk_ses.1.01b8=1; cf_clearance=yBqKgLiEs58dehVpTmbXqGPykQBxDAvICNZCXX5_6F4-1783351737-1.2.1.1-BDxadEI99aea1ee9842FMz6jyUWuCcuhth1Qs8nSg_fh1jhx7823c6mCBwv_FXnIpH9x4F0W7Js1Ld8kYHe58CqhyRDjIjSG5nPOzSXRqAEZ5BUBiozyj7Pq7LTeuA67bHtwI4xz44fMZLyrFoq.qj5LNKYz0rv1eV4sdWxWdwC_XyKCnbZKe8VZLMwb7J2x_NZEW9n8_3wdkZV4LlxE8f.EjzPar1iIlMkAP1bjQzm0NLWAQWkzBmVE78lokS9UBesjWkgNY8o5ye93PSg0A3E.To9leXJF_sw9SLQ8mv7Q.5NCFPLZnGhecvH9SPqwF6qfLRpJkTcXpXv3IpwEhNrYqxr5LfdAcakFG_5bTwWFXhvjguD0bbNl2RDzQ4Z9NfanJ3abchATAyd6INNGrxUksO7F592Ry6vko9T7gRXDA7rPKfINxzDKidNpGEiE; XSRF-TOKEN=eyJpdiI6IjMzTTJBWmlkcU53ODVadWZ6R2xMYVE9PSIsInZhbHVlIjoiaXVLNWFEYys3MkhoUzE5Sm9sS09HalhMTTdDUUhhTHN0bnl2WkU2ekFPYlRDZGZSN1NyU2ZuT2M1cGxlRGlGNyIsIm1hYyI6ImUzMzcyYzAxMzNmYzA4MmYzMGJlMmI0YzdmZjU5MDY5ODFiMTgwYTZhYjgyODMzOWQ4MmIyZTBjZmM5N2NiNWIifQ%3D%3D; wallhaven_session=eyJpdiI6IkhGQTJaS2cwVnRcLzFEYlZsN200WFV3PT0iLCJ2YWx1ZSI6IlFkdU50dnhUVE9VdU9aNitUdWxBb0hUNkErOVwvOU5YQUVuejliS043angrSEp1ZHVMcmpSbVROeEl2YktVQ0hkIiwibWFjIjoiYmEyN2QzOTZkOTI2MzM3ZGY4NTY2ZDdlNzllMjk4MzQ4N2IwMjEzM2QzNWIxMmUxNjhkYWE5ZjAxOGNiZGEyZiJ9""",
        referer=None,
        timeout=15,
        max_tries=3,
        delay=0,
    )


if __name__ == '__main__':
    downloader = create_default_downloader()
    result = downloader.download_pages(MAIN_PAGES)
    print_result(result)

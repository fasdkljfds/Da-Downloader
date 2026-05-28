import os
import re
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
                    print(f"Request failed, retrying {attempt}/{self.max_tries}: {exc}")
                    time.sleep(min(attempt, 5))

        print(f"Request failed after {self.max_tries} tries: {last_error}")
        return None

    def _page_url(self, page: int) -> str:
        if "{page}" in self.site_url:
            return self.site_url.format(page=page)
        separator = "" if self.site_url.endswith(("=", "/", "?")) else ""
        return f"{self.site_url}{separator}{page}"

    def _download(self, image_url: str, save_path: str) -> bool:
        response = self._request(url=image_url)
        if not response:
            return False

        status = getattr(response, "status", None) or getattr(response, "code", None)
        if status != 200:
            return False

        content_type = response.headers.get("content-type", "")
        if content_type and "image" not in content_type.lower():
            return False

        total = int(response.headers.get("content-length", 0))
        temp_path = f"{save_path}.part"
        bar = None
        if tqdm:
            bar = tqdm(
                total=total or None,
                unit="B",
                unit_scale=True,
                unit_divisor=1024,
                desc=os.path.basename(save_path),
            )

        try:
            with open(temp_path, "wb") as f:
                while True:
                    chunk = response.read(1024 * 64)
                    if not chunk:
                        break
                    f.write(chunk)
                    if bar:
                        bar.update(len(chunk))
        finally:
            if bar:
                bar.close()

        os.replace(temp_path, save_path)
        return True
    
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

    def download_image(self, image: str, force: bool = False) -> DownloadResult:
        image_id = self.normalize_image_id(image)
        base_url = self.base_url_for(image_id)
        result = DownloadResult(requested=1)

        if self.cm.exist(base_url) and not force:
            print(f"Skip existing image: {image_id}")
            result.skipped = 1
            return result

        print(f"Download image: {image_id}")
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

    def get_page_image_ids(self, page: int) -> list[str]:
        url = self._page_url(page)
        response = self._request(url=url)
        if not response:
            return []
        status = getattr(response, "status", None) or getattr(response, "code", None)
        if status != 200:
            print(f"Page request failed: HTTP {status} {url}")
            return []

        raw = response.read()
        text = raw.decode("utf-8", errors="ignore")

        patterns = [
            r"https://th\.wallhaven\.cc/small/[^/]+/wallhaven-([A-Za-z0-9]+)\.",
            r"https://wallhaven\.cc/w/([A-Za-z0-9]+)",
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
        result = DownloadResult()
        print(f"Page {page}: found {len(image_ids)} images")

        for image_id in image_ids:
            result.add(self.download_image(image_id, force=force))
            if self.delay > 0:
                time.sleep(self.delay)

        return result

    def download_pages(self, pages: Iterable[int], force: bool = False) -> DownloadResult:
        result = DownloadResult()
        for page in pages:
            result.add(self.download_page(page, force=force))
        return result

    def retry_failed(self, force: bool = True) -> DownloadResult:
        failed = list(self.cm.failed())
        result = DownloadResult()
        print(f"Retry failed images: {len(failed)}")

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


def print_result(result: DownloadResult):
    print(
        "Done: "
        f"requested={result.requested}, "
        f"downloaded={result.downloaded}, "
        f"skipped={result.skipped}, "
        f"failed={result.failed}"
    )

from __future__ import annotations

import os
from enum import Enum

from downloader.wallhaven import DEFAULT_SITE_URL, WallhavenDownloader


class Source(Enum):
    wallhaven = 1
class Library:
    def __init__(
        self,
        source: Source,
        name: str,
        root_dir: str,
        cookie: str | None = None,
        referer: str | None = None,
        site_url: str = DEFAULT_SITE_URL,
    ):
        self.source = source
        self.name = name
        self.root_dir = root_dir
        self.cookie = cookie
        self.referer = referer
        self.site_url = site_url
        
        match self.source:
            case Source.wallhaven:
                self.downloader = self._create_wallhaven_downloader()
            case _:
                raise ValueError(f"Unsupported source: {self.source}")

    def pull_page(self, page: int):
        return self.downloader.download_page(page=page)

    def update(
        self,
        start_page: int = 1,
        max_pages: int | None = None,
        force: bool = False,
        stop_when_known: bool = True,
    ):
        return self.downloader.update(
            start_page=start_page,
            max_pages=max_pages,
            force=force,
            stop_when_known=stop_when_known,
        )

    def _create_wallhaven_downloader(self) -> WallhavenDownloader:
        return WallhavenDownloader(
            save_dir=os.path.join(self.root_dir, self.name, "data"),
            site_url=self.site_url,
            cookie=self.cookie or os.environ.get("WALLHAVEN_COOKIE"),
            referer=self.referer or os.environ.get("WALLHAVEN_REFERER"),
        )


def test_base_logic():
    library = Library(
        source=Source.wallhaven,
        name="test_lib_1",
        root_dir="./libraries",
    )
    library.pull_page(1)


if __name__ == "__main__":
    test_base_logic()

"""Bilibili downloader extension point.

The v1 desktop GUI intentionally ships with Wallhaven support only. Bilibili
requires user-provided authentication and a separate media workflow, so this
module is kept as a safe placeholder instead of storing personal cookies in
source control.
"""


class BilibiliDownloader:
    def __init__(self, *_, **__):
        raise NotImplementedError("Bilibili downloading is not implemented in this version.")


class BilibiliDownloader:
    def __init__(self, ydl_opts: dict[str, Any] | None = None):
        self.ydl_opts = ydl_opts or {}

    # Downloader应该统一暴露一个 download函数，输入资源URL和output_dir，程序自动执行下载逻辑
    def download(self, url: str, output_dir: str | Path) -> dict[str, Any]:
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        options = {
            "format": "bestvideo*+bestaudio/best",
            "outtmpl": str(output_dir / "%(title)s [%(id)s].%(ext)s"),
            "noplaylist": True,
            **self.ydl_opts,
        }

        try:
            with YoutubeDL(options) as ydl:
                info = ydl.extract_info(url, download=True)
        except DownloadError as exc:
            raise RuntimeError(f"Bilibili 视频下载失败：{exc}") from exc

        if info is None:
            raise RuntimeError("下载未返回视频信息")

        return info

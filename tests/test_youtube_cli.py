import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from cli.cli_main import main
from cli.youtube_cli import resolve_youtube_url
from downloader.youtube import DEFAULT_FORMAT_SELCTOR, YoutubeDownloader


class YoutubeCliParsingTest(unittest.TestCase):
    def test_resolve_youtube_url_accepts_direct_url(self):
        self.assertEqual(
            resolve_youtube_url(["https://youtu.be/XtqHoVXCGKU"]),
            "https://youtu.be/XtqHoVXCGKU",
        )
        
    def test_resolve_youtube_url_accepts_download_word(self):
        self.assertEqual(
            resolve_youtube_url(["download", "https://youtu.be/XtqHoVXCGKU"]),
            "https://youtu.be/XtqHoVXCGKU",
        )

    def test_resolve_youtube_url_rejects_ambiguous_targets(self):
        with self.assertRaises(ValueError):
            resolve_youtube_url(["download", "one", "two"])


class YoutubeDownloaderCommandTest(unittest.TestCase):
    def test_build_command_uses_best_video_plus_audio(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            downloader = YoutubeDownloader(save_dir=temp_dir, executable="yt-dlp")
            command = downloader.build_command("https://youtu.be/XtqHoVXCGKU")

        self.assertEqual(command[0], "yt-dlp")
        self.assertIn("--format", command)
        self.assertEqual(command[command.index("--format") + 1], DEFAULT_FORMAT_SELECTOR)
        self.assertIn("--no-playlist", command)
        self.assertEqual(command[-1], "https://youtu.be/XtqHoVXCGKU")


class YoutubeMainTest(unittest.TestCase):
    def test_youtube_json_output(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            video_path = os.path.join(temp_dir, "video.mp4")

            class FakeProcess:
                stdout = [f"{video_path}\n"]

                def wait(self):
                    return 0

            stdout = io.StringIO()
            with patch("downloader.youtube.subprocess.Popen", return_value=FakeProcess()):
                with redirect_stdout(stdout):
                    main(
                        [
                            "youtube",
                            "--yt-dlp",
                            "yt-dlp",
                            "--save-dir",
                            temp_dir,
                            "--json",
                            "https://youtu.be/XtqHoVXCGKU",
                        ]
                    )

            payload = json.loads(stdout.getvalue())
            self.assertEqual(payload["requested"], 1)
            self.assertEqual(payload["downloaded"], 1)
            self.assertEqual(payload["failed"], 0)
            self.assertEqual(payload["files"], [video_path])


if __name__ == "__main__":
    unittest.main()

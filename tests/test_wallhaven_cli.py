import argparse
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch

from cli.cli_main import main, parse_extensions, parse_pages, positive_int
from downloader.wallhaven import DownloadResult, WallhavenDownloader
from infra.context_manager import ContextManager


class CliParsingTest(unittest.TestCase):
    def test_parse_pages_accepts_ranges_and_lists(self):
        self.assertEqual(parse_pages("1,3-5,8"), [1, 3, 4, 5, 8])

    def test_parse_pages_rejects_non_positive_pages(self):
        with self.assertRaises(argparse.ArgumentTypeError):
            parse_pages("0")
        with self.assertRaises(argparse.ArgumentTypeError):
            parse_pages("2-1")

    def test_parse_extensions_normalizes_values(self):
        self.assertEqual(parse_extensions("JPG, png,.JPEG"), (".jpg", ".png", ".jpeg"))

    def test_positive_int_rejects_zero(self):
        self.assertEqual(positive_int("3"), 3)
        with self.assertRaises(argparse.ArgumentTypeError):
            positive_int("0")


class DownloadResultTest(unittest.TestCase):
    def test_to_dict_and_add(self):
        result = DownloadResult(requested=1, downloaded=1, files=["a.jpg"])
        result.add(DownloadResult(requested=2, skipped=1, failed=1, errors=["x"]))

        self.assertEqual(
            result.to_dict(),
            {
                "requested": 3,
                "downloaded": 1,
                "skipped": 1,
                "failed": 1,
                "files": ["a.jpg"],
                "errors": ["x"],
            },
        )


class WallhavenDownloaderTest(unittest.TestCase):
    def test_normalize_image_id_and_page_url(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            downloader = WallhavenDownloader(
                save_dir=temp_dir,
                site_url="https://wallhaven.cc/search?q=test",
            )

            self.assertEqual(
                downloader.normalize_image_id("https://wallhaven.cc/w/abc123"),
                "abc123",
            )
            self.assertEqual(
                downloader.normalize_image_id("wallhaven-abc123.jpg"),
                "abc123",
            )
            self.assertEqual(
                downloader._page_url(2),
                "https://wallhaven.cc/search?q=test&page=2",
            )
            with self.assertRaises(ValueError):
                downloader._page_url(0)


class ContextManagerTest(unittest.TestCase):
    def test_corrupt_history_is_backed_up_and_reset(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            history_path = os.path.join(temp_dir, "history.json")
            with open(history_path, "w", encoding="utf-8") as history_file:
                history_file.write("{bad json")

            manager = ContextManager(history_path)
            self.assertEqual(manager.stats(), {"downloaded": 0, "failed": 0})

            backups = [
                name
                for name in os.listdir(temp_dir)
                if name.startswith("history.json.corrupt.")
            ]
            self.assertEqual(len(backups), 1)
            with open(history_path, "r", encoding="utf-8") as history_file:
                self.assertEqual(json.load(history_file), {"downloaded": [], "failed": []})


class JsonCliTest(unittest.TestCase):
    def test_quick_update_reuses_main_configuration_and_pages(self):
        with patch('cli.wallhaven_cli.create_default_downloader') as factory:
            factory.return_value.download_pages.return_value = DownloadResult(downloaded=2)
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                main(['--json', 'wallhaven', 'quick-update'])

        factory.assert_called_once_with()
        factory.return_value.download_pages.assert_called_once_with((1, 2, 3, 4, 5))
        self.assertEqual(json.loads(stdout.getvalue())['downloaded'], 2)

    def test_main_configuration_is_passed_to_downloader(self):
        from downloader.wallhaven import create_default_downloader

        with patch('downloader.wallhaven.WallhavenDownloader') as factory:
            create_default_downloader()

        options = factory.call_args.kwargs
        self.assertEqual(options['save_dir'], r'F:\estore\wallpaper')
        self.assertEqual(options['extensions'], ('.jpg', '.png', '.jpeg'))
        self.assertEqual(options['site_url'],
                         'https://wallhaven.cc/user/sjjfirk/favorites/2119257?purity=001&page=')
        self.assertTrue(options['cookie'])
        self.assertEqual(options['timeout'], 15)
        self.assertEqual(options['max_tries'], 3)

    def test_status_json_before_source(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            stdout = io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(io.StringIO()):
                main(["--json", "wallhaven", "status", "--save-dir", temp_dir])

            payload = json.loads(stdout.getvalue())
            self.assertEqual(payload["downloaded"], 0)
            self.assertEqual(payload["failed"], 0)
            self.assertEqual(payload["save_dir"], os.path.abspath(temp_dir))

    def test_status_json_after_action(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            stdout = io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(io.StringIO()):
                main(["wallhaven", "status", "--json", "--save-dir", temp_dir])

            payload = json.loads(stdout.getvalue())
            self.assertEqual(payload["downloaded"], 0)
            self.assertEqual(payload["failed"], 0)


if __name__ == "__main__":
    unittest.main()

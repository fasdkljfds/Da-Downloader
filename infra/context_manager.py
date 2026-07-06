import json
import os
import shutil
import time


def _empty_history():
    return {"downloaded": [], "failed": []}


class ContextManager:
    def __init__(self, history_file: str):
        self.history_file = history_file
        self._recovered_corrupt_history = False
        history_dir = os.path.dirname(os.path.abspath(self.history_file))
        os.makedirs(history_dir, exist_ok=True)
        if not os.path.exists(self.history_file):
            self._write_history(_empty_history())

    def _load_history(self):
        if not os.path.exists(self.history_file):
            return _empty_history()
        try:
            with open(self.history_file, 'r', encoding='utf-8') as f:
                history_data = json.load(f)
                return self._normalize_history(history_data)
        except Exception:
            history_data = _empty_history()
            self._backup_corrupt_history()
            self._write_history(history_data)
            return history_data

    def _normalize_history(self, history_data):
        if not isinstance(history_data, dict):
            raise ValueError("history must be a JSON object")

        downloaded = history_data.get("downloaded", [])
        failed = history_data.get("failed", [])
        if not isinstance(downloaded, list) or not isinstance(failed, list):
            raise ValueError("history lists are malformed")

        return {
            "downloaded": [str(item) for item in downloaded],
            "failed": [str(item) for item in failed],
        }

    def _backup_corrupt_history(self):
        if self._recovered_corrupt_history or not os.path.exists(self.history_file):
            return

        self._recovered_corrupt_history = True
        backup_path = f"{self.history_file}.corrupt.{int(time.time())}"
        try:
            shutil.copy2(self.history_file, backup_path)
        except OSError:
            pass

    def _write_history(self, history_data):
        temp_path = f"{self.history_file}.tmp"
        with open(temp_path, 'w', encoding='utf-8') as f:
            json.dump(history_data, f, ensure_ascii=False, indent=4)
            f.write("\n")
        os.replace(temp_path, self.history_file)

    def _save_history(self, url):
        history_data = self._load_history()
        if url not in history_data["downloaded"]:
            history_data["downloaded"].append(url)
        failed_list = history_data.get("failed", [])
        if url in failed_list:
            failed_list.remove(url)
        self._write_history(history_data)

    def _save_error(self, url):
        history_data = self._load_history()
        if url not in history_data["downloaded"] and url not in history_data["failed"]:
            history_data["failed"].append(url)
        self._write_history(history_data)

    def _delete_error(self, url):
        history_data = self._load_history()
        failed_list = history_data.get("failed", [])
        if url in failed_list:
            failed_list.remove(url)
            self._write_history(history_data)

    def exist(self, url) -> bool:
        history_data = self._load_history()
        if url in history_data['downloaded']:
            return True
        return False

    def mark_downloaded(self, url):
        self._save_history(url)

    def mark_error(self, url):
        self._save_error(url)

    def clear_error(self, url):
        self._delete_error(url)

    def downloaded(self):
        return self._load_history()["downloaded"]

    def failed(self):
        return self._load_history()["failed"]

    def stats(self):
        history_data = self._load_history()
        return {
            "downloaded": len(history_data["downloaded"]),
            "failed": len(history_data["failed"]),
        }

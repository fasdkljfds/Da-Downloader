import json
import os


class ContextManager:
    def __init__(self, history_file: str):
        self.history_file = history_file
        history_dir = os.path.dirname(os.path.abspath(self.history_file))
        os.makedirs(history_dir, exist_ok=True)
        if not os.path.exists(self.history_file):
            self._write_history({"downloaded": [], "failed": []})

    def _load_history(self):
        if not os.path.exists(self.history_file):
            return {"downloaded": [], "failed": []}
        try:
            with open(self.history_file, 'r', encoding='utf-8') as f:
                history_data = json.load(f)
                history_data.setdefault("downloaded", [])
                history_data.setdefault("failed", [])
                return history_data
        except Exception:
            return {"downloaded": [], "failed": []}

    def _write_history(self, history_data):
        with open(self.history_file, 'w', encoding='utf-8') as f:
            json.dump(history_data, f, ensure_ascii=False, indent=4)

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
        if url not in history_data["failed"]:
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

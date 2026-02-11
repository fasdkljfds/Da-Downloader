import json
import os

class ContextManager:
    def __init__(self, history_file: str):
        self.history_file = history_file
        if not os.path.exists(self.history_file):
            with open(self.history_file, 'w', encoding='utf-8') as f:
                history_data = {"downloaded": [], "failed": []}
                json.dump(history_data, f, ensure_ascii=False, indent=4)

    def _load_history(self):
        if not os.path.exists(self.history_file):
            return {"downloaded": [], "failed": []}
        try:
            with open(self.history_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            return {"downloaded": [], "failed": []}

    def _save_history(self, url):
        """
        Args:
             url: e.g. https://w.wallhaven.cc/full/zp/wallhaven-zpzd3j no format
        """
        history_data = self._load_history()
        history_data["downloaded"].append(url)
        with open(self.history_file, 'w', encoding='utf-8') as f:
            json.dump(history_data, f, ensure_ascii=False, indent=4)

    def _save_error(self, url):
        history_data = self._load_history()
        history_data["failed"].append(url)
        with open(self.history_file, 'w', encoding='utf-8') as f:
            json.dump(history_data, f, ensure_ascii=False, indent=4)

    def _delete_error(self, url):
        history_data = self._load_history()
        failed_list = history_data.get("failed", [])
        if url in failed_list:
            failed_list.remove(url)
            with open(self.history_file, 'w', encoding='utf-8') as f:
                json.dump(history_data, f, ensure_ascii=False, indent=4)

    def exist(self, url) -> bool:
        history_data = self._load_history()
        if url in history_data['downloaded']:
            return True
        return False

    def mark_downloaded(self, url):
        self._save_history(url)

    def mark_error(self, url):
        self._save_error(url)

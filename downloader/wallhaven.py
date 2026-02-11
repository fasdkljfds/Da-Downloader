import requests
import regex
import os
from infra.context_manager import ContextManager
from tqdm import tqdm
from requests import Response


class WallhavenDownloader:
    def __init__(self, EXTENSIONS: list[str], SITE_URL: str, COOKIE: str, REFERER: str, save_dir: str):
        self.EXTENSIONS = EXTENSIONS
        self.SITE_URL = SITE_URL
        self.COOKIE = COOKIE
        self.REFERER = REFERER

        self.save_dir = save_dir
        os.makedirs(self.save_dir, exist_ok=True)

        self.cm = ContextManager(history_file=self.save_dir + '/history.json')

    def _request(self, url: str, max_tries: int = 3, timeout: int = 5) -> None | Response:
        for i in range(max_tries):
            if i > 0:
                print(f'>> 重试第 {i} 次')
            try:
                return requests.get(url, stream=True, timeout=timeout)
            except Exception as e:
                print(f">> 服务器无法连接 {e}")

        return None

    def _download(self, image_url: str, save_path: str) -> bool:
        """
        Args:
            image_url: e.g. https://w.wallhaven.cc/full/1k/wallhaven-1k38pw.jpg
        """

        response = self._request(url=image_url)
        if not response:
            return False

        if response.status_code == 200:
            with open(save_path, 'wb') as f, tqdm(
                    unit='B',
                    unit_scale=True,
                    unit_divisor=1024,
                    desc='process'
            ) as bar:
                for c in response.iter_content(chunk_size=1024):
                    if c:
                        f.write(c)
                        bar.update(len(c))
            return True

        return False

    def _download_single_image(self, image_name: str) -> bool:
        """
        Args:
            image_name: e.g. 1k38pw
        """
        print(f'Start downloading {image_name}')

        base_url = f"https://w.wallhaven.cc/full/{image_name[:2]}/wallhaven-{image_name}"

        if self.cm.exist(base_url):
            print(f'{image_name} exists')
            return True

        for ext in self.EXTENSIONS:
            url = base_url + ext
            filename = image_name + ext
            save_path = os.path.join(self.save_dir, filename)

            if self._download(image_url=url, save_path=save_path):
                self.cm.mark_downloaded(base_url)
                return True
            print(f'{ext} format not exists')

        self.cm.mark_error(base_url)
        return False

    def _get_page_image_names(self, page: int) -> list[str]:
        url = self.SITE_URL + str(page)
        response = requests.get(
            url=url,
            headers={
                'User-Agent': '''Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0''',
                'Cookie': self.COOKIE,
                'Referer': self.REFERER
            }
        )
        pattern = r'https://th\.wallhaven\.cc/small/[^/]+/([^.]+)'
        names = regex.findall(pattern, response.text)

        return names

    def download_page(self, page: int):
        image_names = self._get_page_image_names(page=page)
        for n in image_names:
            self._download_single_image(image_name=n)


def test_download_single_image():
    downloader = WallhavenDownloader(
        EXTENSIONS=['.jpg', '.png'],
        SITE_URL='https://wallhaven.cc/favorites?page=',
        COOKIE='''_pk_id.1.01b8=4ba6e2403d32ff0e.1766719365.; remember_web_59ba36addc2b2f9401580f014c7f58ea4e30989d=eyJpdiI6Im8ycHhnUzlkdnFnS0ZBMVBTa3c0dWc9PSIsInZhbHVlIjoiYWYraTVUZW1GM0VqTU5XUm0rQmxGa1FRcGJPb0JheFJhdFJXUkYxSFM5Mk1Ec1hnMWF5WU5jb0NjSkpacXlMRlIzRCtDc0pGUldIZzIyMTU4N2NpOHhjWUI3M0NUTzZGbGcrYWlKWTZDajY0aDVZQWMrT2lLRGxuZTlFSEZSNUt3VitnT1Y5ZTM0Z1ZQdERcL1NMRGxXdTNNMnJHR3lIblpMR21jeGpXbXF3VVRNWnBFU3IzSlpKemVUdFE2elFIdiIsIm1hYyI6ImMxYTE1NmMwM2JjZjlkYzQ0N2Q2ODhiZjIwNDU1MWJmN2U1YmUzYmIwZjM3MzcyYWJkNDhkM2E3MjRmZTYwZGUifQ%3D%3D; _pk_ref.1.01b8=%5B%22%22%2C%22%22%2C1769252212%2C%22https%3A%2F%2Fwww.google.com%2F%22%5D; _pk_ses.1.01b8=1; cf_clearance=qPh5K.zV6FCqbOhlXjVBQ_CqdFXbLW0aMRM7NGtuiCw-1769254797-1.2.1.1-G5EfZcwO92n_LpF7VSUfaV0SNm_pXha7nHYC5dysU7sZOMMPzkghe2yoWIJS6KsoUWwNUyI6k.IirKpjA1FXCa9R4Kxlvw615ig1bu4PRoSbcuQ4GZYZ8IBaptJBnkmHcSaa3rZGQ2Q3HhHuoVgSSqwLL64hL8Cx7xL00H6mEVyERVDY3y1oe4ogp7LY4FLzauoNWxDjpPQohRT0Kd9n0n6MsUId2NemIc_ufhPzzEI; XSRF-TOKEN=eyJpdiI6InBHVXhkYzRPNFM3S3pvQWJIQ0JXVFE9PSIsInZhbHVlIjoicWI5YVwvdktOMVczejJ0WU1oRWNtNjB4ZU90K2tmRVYwK2txZzFseEZTV3k0M0RxdVZpT3luSGpDdlZyQ1ZGRWgiLCJtYWMiOiI3ZDQ4NGY5MzBiYjhiYmMxYmNhMjljOTU3NGE0MmU3OWU1MWM5OWY5ZDQ3YjcwOTYxNzNmZjEyZmNhMjE2OWI1In0%3D; wallhaven_session=eyJpdiI6ImxVRGlWVFc1ZVpVblhhYm5vUjROUHc9PSIsInZhbHVlIjoiekhMWHB6dW5penVoNTZXQ09oV1lkbXlqMUNqSEdncWJvNTNkTXh4Rm1MYWZQQlF2Uk4xMmxzaVVGR1hPOGNcLzYiLCJtYWMiOiJmNWM1ZGMzNzdlYzlkZGZhMTdlM2I3ZmI0YjM1OGQ2Y2I2ZjM4NmFlOWIyMGU2MWJmZWNiM2EzZjM5MjI2NjZhIn0%3D''',
        REFERER='https://wallhaven.cc/user/sjjfirk',

        save_dir='./test'
    )
    downloader._download_single_image('1k38pw')
    downloader._download_single_image('og1995')


def test_download_page():
    downloader = WallhavenDownloader(
        EXTENSIONS=['.jpg', '.png'],
        SITE_URL='https://wallhaven.cc/favorites?page=',
        COOKIE='''_pk_id.1.01b8=4ba6e2403d32ff0e.1766719365.; remember_web_59ba36addc2b2f9401580f014c7f58ea4e30989d=eyJpdiI6Im8ycHhnUzlkdnFnS0ZBMVBTa3c0dWc9PSIsInZhbHVlIjoiYWYraTVUZW1GM0VqTU5XUm0rQmxGa1FRcGJPb0JheFJhdFJXUkYxSFM5Mk1Ec1hnMWF5WU5jb0NjSkpacXlMRlIzRCtDc0pGUldIZzIyMTU4N2NpOHhjWUI3M0NUTzZGbGcrYWlKWTZDajY0aDVZQWMrT2lLRGxuZTlFSEZSNUt3VitnT1Y5ZTM0Z1ZQdERcL1NMRGxXdTNNMnJHR3lIblpMR21jeGpXbXF3VVRNWnBFU3IzSlpKemVUdFE2elFIdiIsIm1hYyI6ImMxYTE1NmMwM2JjZjlkYzQ0N2Q2ODhiZjIwNDU1MWJmN2U1YmUzYmIwZjM3MzcyYWJkNDhkM2E3MjRmZTYwZGUifQ%3D%3D; _pk_ref.1.01b8=%5B%22%22%2C%22%22%2C1769252212%2C%22https%3A%2F%2Fwww.google.com%2F%22%5D; _pk_ses.1.01b8=1; cf_clearance=qPh5K.zV6FCqbOhlXjVBQ_CqdFXbLW0aMRM7NGtuiCw-1769254797-1.2.1.1-G5EfZcwO92n_LpF7VSUfaV0SNm_pXha7nHYC5dysU7sZOMMPzkghe2yoWIJS6KsoUWwNUyI6k.IirKpjA1FXCa9R4Kxlvw615ig1bu4PRoSbcuQ4GZYZ8IBaptJBnkmHcSaa3rZGQ2Q3HhHuoVgSSqwLL64hL8Cx7xL00H6mEVyERVDY3y1oe4ogp7LY4FLzauoNWxDjpPQohRT0Kd9n0n6MsUId2NemIc_ufhPzzEI; XSRF-TOKEN=eyJpdiI6InBHVXhkYzRPNFM3S3pvQWJIQ0JXVFE9PSIsInZhbHVlIjoicWI5YVwvdktOMVczejJ0WU1oRWNtNjB4ZU90K2tmRVYwK2txZzFseEZTV3k0M0RxdVZpT3luSGpDdlZyQ1ZGRWgiLCJtYWMiOiI3ZDQ4NGY5MzBiYjhiYmMxYmNhMjljOTU3NGE0MmU3OWU1MWM5OWY5ZDQ3YjcwOTYxNzNmZjEyZmNhMjE2OWI1In0%3D; wallhaven_session=eyJpdiI6ImxVRGlWVFc1ZVpVblhhYm5vUjROUHc9PSIsInZhbHVlIjoiekhMWHB6dW5penVoNTZXQ09oV1lkbXlqMUNqSEdncWJvNTNkTXh4Rm1MYWZQQlF2Uk4xMmxzaVVGR1hPOGNcLzYiLCJtYWMiOiJmNWM1ZGMzNzdlYzlkZGZhMTdlM2I3ZmI0YjM1OGQ2Y2I2ZjM4NmFlOWIyMGU2MWJmZWNiM2EzZjM5MjI2NjZhIn0%3D''',
        REFERER='https://wallhaven.cc/user/sjjfirk',

        save_dir='../libraries/test_lib'
    )
    downloader.download_page(page=1)

if __name__ == '__main__':
    test_download_page()

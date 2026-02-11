from enum import Enum

from downloader.wallhaven import WallhavenDownloader


class Source(Enum):
    wallhaven = 1


class Library:
    def __init__(self, source: Source, name: str, root_dir: str):
        self.source = source
        self.name = name
        self.root_dir = root_dir
        match self.source:
            case Source.wallhaven:
                self.downloader = self._create_wallhaven_downloader()

    def pull_page(self, page: int):
        self.downloader.download_page(page=page)

    def _create_wallhaven_downloader(self) -> WallhavenDownloader:
        return WallhavenDownloader(
        EXTENSIONS=['.jpg', '.png'],
        SITE_URL='https://wallhaven.cc/favorites?page=',
        COOKIE='''_pk_id.1.01b8=4ba6e2403d32ff0e.1766719365.; remember_web_59ba36addc2b2f9401580f014c7f58ea4e30989d=eyJpdiI6Im8ycHhnUzlkdnFnS0ZBMVBTa3c0dWc9PSIsInZhbHVlIjoiYWYraTVUZW1GM0VqTU5XUm0rQmxGa1FRcGJPb0JheFJhdFJXUkYxSFM5Mk1Ec1hnMWF5WU5jb0NjSkpacXlMRlIzRCtDc0pGUldIZzIyMTU4N2NpOHhjWUI3M0NUTzZGbGcrYWlKWTZDajY0aDVZQWMrT2lLRGxuZTlFSEZSNUt3VitnT1Y5ZTM0Z1ZQdERcL1NMRGxXdTNNMnJHR3lIblpMR21jeGpXbXF3VVRNWnBFU3IzSlpKemVUdFE2elFIdiIsIm1hYyI6ImMxYTE1NmMwM2JjZjlkYzQ0N2Q2ODhiZjIwNDU1MWJmN2U1YmUzYmIwZjM3MzcyYWJkNDhkM2E3MjRmZTYwZGUifQ%3D%3D; _pk_ref.1.01b8=%5B%22%22%2C%22%22%2C1769252212%2C%22https%3A%2F%2Fwww.google.com%2F%22%5D; _pk_ses.1.01b8=1; cf_clearance=qPh5K.zV6FCqbOhlXjVBQ_CqdFXbLW0aMRM7NGtuiCw-1769254797-1.2.1.1-G5EfZcwO92n_LpF7VSUfaV0SNm_pXha7nHYC5dysU7sZOMMPzkghe2yoWIJS6KsoUWwNUyI6k.IirKpjA1FXCa9R4Kxlvw615ig1bu4PRoSbcuQ4GZYZ8IBaptJBnkmHcSaa3rZGQ2Q3HhHuoVgSSqwLL64hL8Cx7xL00H6mEVyERVDY3y1oe4ogp7LY4FLzauoNWxDjpPQohRT0Kd9n0n6MsUId2NemIc_ufhPzzEI; XSRF-TOKEN=eyJpdiI6InBHVXhkYzRPNFM3S3pvQWJIQ0JXVFE9PSIsInZhbHVlIjoicWI5YVwvdktOMVczejJ0WU1oRWNtNjB4ZU90K2tmRVYwK2txZzFseEZTV3k0M0RxdVZpT3luSGpDdlZyQ1ZGRWgiLCJtYWMiOiI3ZDQ4NGY5MzBiYjhiYmMxYmNhMjljOTU3NGE0MmU3OWU1MWM5OWY5ZDQ3YjcwOTYxNzNmZjEyZmNhMjE2OWI1In0%3D; wallhaven_session=eyJpdiI6ImxVRGlWVFc1ZVpVblhhYm5vUjROUHc9PSIsInZhbHVlIjoiekhMWHB6dW5penVoNTZXQ09oV1lkbXlqMUNqSEdncWJvNTNkTXh4Rm1MYWZQQlF2Uk4xMmxzaVVGR1hPOGNcLzYiLCJtYWMiOiJmNWM1ZGMzNzdlYzlkZGZhMTdlM2I3ZmI0YjM1OGQ2Y2I2ZjM4NmFlOWIyMGU2MWJmZWNiM2EzZjM5MjI2NjZhIn0%3D''',
        REFERER='https://wallhaven.cc/user/sjjfirk',

        save_dir=self.root_dir + '/' + self.name + '/data'
    )

def test_base_logic():
    l = Library(
        source=Source.wallhaven,
        name='test_lib_1',
        root_dir='./libraries'
    )
    l.pull_page(1)

if __name__ == '__main__':
    test_base_logic()


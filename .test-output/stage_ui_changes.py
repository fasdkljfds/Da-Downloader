from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]


def git(*args, **kwargs):
    return subprocess.check_output(
        ['git', '-c', f'safe.directory={root.as_posix()}', *args],
        cwd=root, **kwargs,
    )


files = [
    '.gitignore', 'cli/wallhaven_cli.py', 'downloader/wallhaven.py',
    'tests/test_wallhaven_cli.py', 'wallpaper/README.md',
    'wallpaper/lib/main.dart', 'wallpaper/lib/hidden_wallpapers.dart',
    'wallpaper/test/widget_test.dart', 'wallpaper/test/gallery_behavior_test.dart',
    'wallpaper/tool/gallery_smoke.dart',
]
git('add', '--', *files)

# Keep the pre-existing local Cookie edit out of the UI commit.
path = 'downloader/wallhaven.py'
baseline = git('show', f'HEAD:{path}').decode('utf-8')
staged = git('show', f':{path}').decode('utf-8')
pattern = r'^        cookie=.*$'
original_cookie = re.search(pattern, baseline, re.MULTILINE)
assert original_cookie is not None
staged, count = re.subn(pattern, lambda _: original_cookie.group(), staged, flags=re.MULTILINE)
assert count == 1
blob = git('hash-object', '-w', '--stdin', f'--path={path}', input=staged.encode('utf-8')).decode().strip()
git('update-index', '--cacheinfo', f'100644,{blob},{path}')

library = (root / 'libraries').resolve()
assert library.parent == root and library.name == 'libraries'
tracked = git('ls-files', '-z', '--', 'libraries').decode('utf-8').split('\0')
existing = [root / name for name in tracked if name and (root / name).exists()]
git('rm', '-r', '--cached', '--', 'libraries')
assert all(path.exists() for path in existing)
print(f'Staged UI changes; untracked {len(existing)} library files without deleting local files.')

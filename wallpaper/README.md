# Da Downloader GUI

Windows desktop Flutter GUI for the Wallhaven downloader in this repository.

## Run

From `wallpaper/`:

```powershell
flutter run -d windows
```

The app calls the Python CLI through `py -B -m cli.cli_main --json ...`, so run it from this repo with `py.exe` available on PATH.

## Checks

```powershell
flutter analyze
flutter test
```

Python checks from the repo root:

```powershell
py -B -m unittest discover -v
```

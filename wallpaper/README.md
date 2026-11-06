# Da Downloader GUI

Windows desktop Flutter GUI for the Wallhaven downloader in this repository.

## Run

From `wallpaper/`:

```powershell
flutter run -d windows
```

左侧只保留「一键更新」，右侧显示本地图库，支持双击预览和设为壁纸。

缩略图按 512 像素宽解码，双击以轻微缩放和淡入动画打开预览，返回时淡出。预览覆盖在原图库上，返回或按 Esc 关闭时保留缩略图和滚动位置。

选中图片后点击顶部「隐藏所选壁纸」，或在放大预览中点击「隐藏这张壁纸」，可以手动隐藏 NSFW 图片。点击顶部「查看已隐藏」可逐张恢复。隐藏记录保存在图库目录的 `.hidden-wallpapers.json`，重启后生效，原文件不会删除。

点击顶部「多选壁纸」后可点选或取消多张图片，再批量隐藏或恢复。也支持 Ctrl 点选、Shift 连选，以及多选模式下的「全选」。Esc 可退出多选。缩略图松开鼠标即选中，边框即时显示；双击仍可预览。

The app calls `py -B -m cli.cli_main --json wallhaven quick-update`, so run it from this repo with `py.exe` available on PATH.

更新复用 `downloader/wallhaven.py` 中的 `create_default_downloader()`，与脚本主入口使用同一份配置（包含 Cookie），下载第 1–5 页并跳过已有图片。下载目录与当前图库一致。直接运行应用时，优先使用 `DA_WALLPAPER_DIR` 指定的目录，其次使用已存在的 `F:\estore\wallpaper`，最后使用仓库内的 `libraries/wallpaper-sync`。

## Checks

```powershell
flutter analyze
flutter test
```

原生桌面回归可使用合成 4K 图片库，避免修改真实图库：

```powershell
flutter run -d windows -t tool/gallery_smoke.dart
```

Python checks from the repo root:

```powershell
py -B -m unittest discover -v
```

构建 Windows 程序：

```powershell
flutter build windows
```

Windows 构建会通过 `Runner.rc` 将 `windows/runner/resources/app_icon.ico` 嵌入 EXE。图标的矢量源文件是同目录下的 `app_icon.svg`。修改 SVG 后，请重新生成多尺寸 ICO 再构建。

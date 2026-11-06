# Da Downloader

依旧就爱用自己写的软件

## 在另一台 Windows 电脑部署壁纸应用

首次准备 Git for Windows（含 Git LFS）、Python 3.10 或更新版本（含 `py` 启动器）、Flutter，以及 Visual Studio 的「使用 C++ 的桌面开发」工作负载。

```powershell
git clone https://github.com/fasdkljfds/project04.git
cd project04
.\deploy-wallpaper.cmd
```

已克隆的电脑先运行 `git pull`。也可以双击 `deploy-wallpaper.cmd`。脚本会补齐 Git LFS 壁纸、构建并打开应用。「一键更新」会将新壁纸下载到当前图库 `libraries/wallpaper-sync`。

仓库中的同步图库只包含导出时可见的图片。之后在应用里隐藏图片会更新本机记录。

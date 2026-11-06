@echo off
setlocal
pushd "%~dp0" || goto failed
set "DA_WALLPAPER_DIR=%CD%\libraries\wallpaper-sync"

git lfs version >nul 2>&1 || (
  echo Install Git for Windows with Git LFS, then try again.
  goto failed
)
where.exe flutter >nul 2>&1 || (
  echo Install Flutter and add it to PATH, then try again.
  goto failed
)
py -B -c "import sys; sys.exit(sys.version_info < (3, 10))" || (
  echo Install Python 3.10 or later with the Windows Python launcher.
  goto failed
)

git lfs pull --include="libraries/wallpaper-sync/**" --exclude="" || goto failed
cd wallpaper || goto failed
call flutter run -d windows --release
if errorlevel 1 goto failed
popd
exit /b 0

:failed
echo Deployment failed. See the message above.
pause
exit /b 1

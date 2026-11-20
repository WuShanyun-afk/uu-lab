@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 (
  echo.
  echo   没有找到 Python。请先安装 Python 3，或改用任意静态服务器打开这个文件夹。
  echo   也可以直接把整个文件夹部署到 GitHub Pages / Netlify。
  echo.
  pause
  exit /b 1
)

set PORT=4173
echo.
echo   Lian 本地预览：http://127.0.0.1:%PORT%/
echo   关闭这个窗口即可停止服务器。
echo.

start "Lian Browser" cmd /c "timeout /t 2 >nul & start http://127.0.0.1:%PORT%/"
python -m http.server %PORT% --bind 127.0.0.1

@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 (
  echo.
  echo   Python 3 was not found. Install Python, or serve this folder with any static server.
  echo   You can also deploy the whole folder to GitHub Pages / Netlify.
  echo.
  pause
  exit /b 1
)

set PORT=4173
echo.
echo   Lian local preview: http://127.0.0.1:%PORT%/
echo   Close this window to stop the server.
echo.

start "Lian Browser" cmd /c "timeout /t 2 >nul & start http://127.0.0.1:%PORT%/"
python -m http.server %PORT% --bind 127.0.0.1

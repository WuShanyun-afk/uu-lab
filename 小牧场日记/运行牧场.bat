@echo off
rem ============================================================
rem  Little Ranch Diary -- windowed launcher
rem  640x360 internal, integer scaled. F11 toggles fullscreen.
rem  This file is pure ASCII on purpose: cmd.exe decodes .bat
rem  bytes with the system codepage, so non-ASCII here = mojibake.
rem ============================================================
setlocal enabledelayedexpansion
title Little Ranch Diary

set "GODOT="
for %%n in (godot.exe godot4.exe Godot_v4.7.2-stable_win64.exe) do (
  if not defined GODOT (
    for /f "delims=" %%p in ('where %%n 2^>nul') do if not defined GODOT set "GODOT=%%p"
  )
)

if not defined GODOT (
  for /d %%d in ("%USERPROFILE%\.godot-mcp\godot\*") do (
    if not defined GODOT (
      for %%f in ("%%~d\Godot*.exe") do if not defined GODOT set "GODOT=%%~ff"
    )
  )
)

if not defined GODOT (
  echo.
  echo   [x] Godot not found.
  echo       Put Godot on PATH, or hardcode its exe path in this file.
  echo.
  pause
  exit /b 1
)

pushd "%~dp0"
echo   Godot : %GODOT%
echo   Project: %CD%
echo.
start "" "%GODOT%" --path "%CD%"
popd
endlocal

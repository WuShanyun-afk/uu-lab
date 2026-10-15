@echo off
title MCP 导入助手
echo ============================================================
echo   MCP 导入助手
echo ============================================================
echo.
echo  [1/2] 把 mcp-import.json 复制到剪贴板...
powershell -NoProfile -Command "Get-Content -Raw -Encoding UTF8 '%~dp0小牧场日记\_uu\mcp-import.json' | Set-Clipboard"
echo        完成。
echo.
echo  [2/2] 打开文件所在文件夹...
start "" explorer "%~dp0小牧场日记\_uu"
echo.
echo ------------------------------------------------------------
echo  Kelivo 里的操作（千万别粘到 URL 字段！）：
echo.
echo   设置 -^> MCP -^> 添加服务器 -^> 找「JSON 导入」
echo   把剪贴板内容粘进去 -^> 保存
echo.
echo   然后删掉之前那条错的（名字叫 MCP、transport=http 的那条）
echo.
echo   最后完全退出 Kelivo 再打开（任务栏右键退出，不是关窗口）
echo ------------------------------------------------------------
echo.
pause

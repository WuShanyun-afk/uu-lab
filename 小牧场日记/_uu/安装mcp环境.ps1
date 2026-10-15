# 小牧场日记 — MCP 环境引导脚本
# 用法:  powershell -ExecutionPolicy Bypass -File "D:\UU的办公室\小牧场日记\_uu\安装MCP环境.ps1"
# 幂等：已装的跳过，不覆盖任何已有配置。
# 注意：本文件必须保存为 UTF-8 with BOM，否则 Windows PowerShell 5.1 会把中文路径读成乱码。

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\UU的办公室\小牧场日记'

function Say  { param($t) Write-Host "`n>>> $t" -ForegroundColor Cyan }
function OK   { param($t) Write-Host "    [OK]   $t" -ForegroundColor Green }
function Skip { param($t) Write-Host "    [SKIP] $t" -ForegroundColor DarkGray }
function Warn { param($t) Write-Host "    [WARN] $t" -ForegroundColor Yellow }

Say '0/6  环境体检'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js 缺失，请先安装 Node >= 20' }
$nodeVer = (& node -v)
if ([int]($nodeVer.TrimStart('v').Split('.')[0]) -lt 20) { throw "Node $nodeVer 过低，需要 >= 20" }
OK "Node $nodeVer"
OK "npm  $(& npm -v)"
if (Get-Command git -ErrorAction SilentlyContinue) { OK "git  $(& git --version)" } else { Warn 'git 缺失' }

Say '1/6  创建项目目录'
$dirs = @(
    'assets\tilesets', 'assets\sprites\animals', 'assets\characters\npcs',
    'assets\audio\sfx', 'assets\audio\bgm', 'data\csv', 'data\resources',
    'scenes\world', 'scenes\entities', 'scenes\ui',
    'scripts\entities', 'scripts\data', 'qa', '_uu'
)
foreach ($d in $dirs) {
    $p = Join-Path $ProjectRoot $d
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null; OK $d }
    else { Skip $d }
}

Say '2/6  uv / uvx  (lpc-character-mcp 必需)'
if (Get-Command uvx -ErrorAction SilentlyContinue) {
    Skip "uv 已装: $(& uv --version)"
} else {
    Write-Host '    正在安装 uv ...' -ForegroundColor DarkGray
    powershell -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex"
    $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
    if (Get-Command uvx -ErrorAction SilentlyContinue) { OK "uv $(& uv --version)" }
    else { Warn 'uv 装完但当前会话 PATH 未刷新，请重开终端后重跑本脚本' }
}

Say '3/6  Godot 4.7.2-stable  (godot-mcp-enhanced 自带安装器)'
if (Test-Path "$env:USERPROFILE\.godot-mcp\godot") {
    Skip "已存在 $env:USERPROFILE\.godot-mcp\godot"
} else {
    Write-Host '    下载 Godot（官方 GitHub releases，SHA512 校验）...' -ForegroundColor DarkGray
    & npx -y godot-mcp-enhanced install
}
& npx -y godot-mcp-enhanced doctor

Say '4/6  lpc-character-mcp 素材定义（一次性，约 10s）'
if (Test-Path "$env:USERPROFILE\lpc-characters") { Skip '定义已就绪' }
else { & uvx lpc-character-mcp --setup }

Say '5/6  预拉取 npm 型 MCP server（避免首次调用超时）'
foreach ($pkg in @('godot-mcp-enhanced', 'pixelforge-mcp', '@pixelbananas/mcp')) {
    Write-Host "    pulling $pkg ..." -ForegroundColor DarkGray
    $v = & npm view $pkg version 2>$null
    if ($v) { OK "$pkg@$v" } else { Warn "$pkg 拉取失败" }
}

Say '6/6  检查 MCP 配置模板'
$cfg = Join-Path $ProjectRoot '_uu\mcp-config.json'
if (Test-Path $cfg) { OK "配置模板: $cfg" } else { Warn 'mcp-config.json 缺失' }

Write-Host @'

============================================================
  环境就绪。剩下 3 件事需要你手动做：
============================================================
  1. 申请 API Key（都有免费档）：
       GEMINI_API_KEY          https://aistudio.google.com/apikey
       PIXELBANANAS_TOKEN      https://pixelbananas.pages.dev/settings/tokens
  2. 把 _uu\mcp-config.json 的内容并进你的 MCP 客户端配置，
     替换里面所有 REPLACE_ME 占位符。
  3. 重开终端，跑：
       npx godot-mcp-enhanced doctor
     全绿即可开工。
============================================================
'@ -ForegroundColor White

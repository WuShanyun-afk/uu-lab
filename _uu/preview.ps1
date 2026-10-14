# 小鲸鱼的作品集 · 本地预览
# 由办公室的 看作品.bat 调用；也可以右键“使用 PowerShell 运行”
# 作用：在本机起一个只读小服务器，浏览器里直接看画廊，改完 HTML 刷新就行

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$office = Split-Path -Parent $PSScriptRoot

# ---------- 1. 找站点 ----------
$cands = @(
    (Join-Path $office '小鲸鱼的作品集'),
    (Join-Path $office 'QwQCAT-and-D'),
    'D:\小鲸鱼的专属文件夹'
)
$site = $cands | Where-Object { $_ -and (Test-Path (Join-Path $_ 'gallery.html')) } | Select-Object -First 1

if (-not $site) {
    Write-Host ""
    Write-Host "  找不到作品集（没看到 gallery.html）。" -ForegroundColor Red
    Write-Host "  办公室目录：$office" -ForegroundColor DarkGray
    exit 1
}

# ---------- 2. 找 python ----------
$py = $null
$cmd = Get-Command python -ErrorAction SilentlyContinue
if ($cmd) { $py = $cmd.Source }
if (-not $py) {
    foreach ($p in @(
        (Join-Path $env:ProgramFiles 'Python314\python.exe'),
        (Join-Path $env:ProgramFiles 'Python313\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python314\python.exe')
    )) { if (Test-Path $p) { $py = $p; break } }
}
if (-not $py) {
    Write-Host ""
    Write-Host "  找不到 python，起不了服务器。" -ForegroundColor Red
    Write-Host "  救急办法：直接双击 gallery.html 也能看，只是某些浏览器限制略多。" -ForegroundColor DarkGray
    exit 1
}

# ---------- 3. 挑一个空闲端口 ----------
$port = 0
foreach ($try in 8000..8010) {
    try {
        $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $try)
        $l.Start(); $l.Stop()
        $port = $try
        break
    } catch { }
}
if ($port -eq 0) {
    Write-Host "  8000~8010 全被占了，先把别的服务器关掉。" -ForegroundColor Red
    exit 1
}

$url = "http://127.0.0.1:$port/gallery.html"

Write-Host ""
Write-Host "  ===== 小鲸鱼的作品集 · 本地预览 =====" -ForegroundColor Cyan
Write-Host ""
Write-Host "  站点：$site" -ForegroundColor DarkGray
Write-Host "  网址：$url" -ForegroundColor Green
Write-Host "  首页：http://127.0.0.1:$port/" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  改完 HTML 直接刷新浏览器就看到了，不用等 GitHub。" -ForegroundColor DarkGray
Write-Host "  看完了按 Ctrl+C 或直接关掉这个窗口，服务器就停。" -ForegroundColor DarkGray
Write-Host ""

Start-Process $url | Out-Null

& $py -m http.server $port --directory $site

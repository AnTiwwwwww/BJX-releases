# 每次点个人匹配之前，把绝境面板底部「本周还可获得飞沙令」右边的数字记下来。
# MXU 正在写的日志在仓库 debug\maafw.log。传进来的库目录可能是另一份旧日志。
# 记不到也退出 0，不打断排队。邮件在本进程里发完，避免命令结束时子进程被杀掉。
param(
    [Parameter(Position = 0)]
    [string] $LibraryDir = "",
    [Parameter(Position = 1)]
    [string] $Box = ""
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "bjx-log.ps1")

function Write-Left([string] $Remain) {
    $dir = Join-Path (Split-Path $PSScriptRoot -Parent) "debug"
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    $path = Join-Path $dir "royale-weekly-left.txt"
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Remain
    [System.IO.File]::AppendAllText($path, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Write-Output "royale-left=$Remain"
    Write-BjxLog "飞沙令剩余 $Remain"
    $mailer = Join-Path $PSScriptRoot "send-royale-mail.ps1"
    if (Test-Path -LiteralPath $mailer) {
        & $mailer $line
    }
}

function Get-LiveLogs([string] $Library) {
    $raw = @()
    $raw += Join-Path (Split-Path $PSScriptRoot -Parent) "debug\maafw.log"
    $lib = $Library.Trim()
    if ($lib.StartsWith("\\?\")) { $lib = $lib.Substring(4) }
    elseif ($lib.StartsWith("//?/")) { $lib = $lib.Substring(4) }
    if (-not [string]::IsNullOrWhiteSpace($lib)) {
        $raw += Join-Path $lib "debug\maafw.log"
    }
    $seen = @{}
    $items = @()
    foreach ($path in $raw) {
        if ($seen.ContainsKey($path)) { continue }
        $seen[$path] = $true
        if (Test-Path -LiteralPath $path) {
            $items += Get-Item -LiteralPath $path
        }
    }
    return @($items | Sort-Object LastWriteTime -Descending)
}

function Find-Remain([string] $Text, [string] $BoxKey) {
    $needle = '"box":' + $BoxKey
    $at = $Text.Length
    for ($n = 0; $n -lt 8; $n++) {
        if ($at -le 0) { return $null }
        $at = $Text.LastIndexOf($needle, $at - 1)
        if ($at -lt 0) { return $null }
        $slice = $Text.Substring($at, [Math]::Min(240, $Text.Length - $at))
        $m = [regex]::Match($slice, '"text":"([0-9]{1,5})"')
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return $null
}

try {
    $boxKey = ($Box -replace "\s", "")
    if ([string]::IsNullOrWhiteSpace($boxKey)) {
        Write-Left "未能读出"
        exit 0
    }
    $logs = @(Get-LiveLogs $LibraryDir)
    $remain = $null
    for ($try = 0; $try -lt 4 -and -not $remain; $try++) {
        foreach ($item in $logs) {
            $fs = [System.IO.File]::Open($item.FullName, "Open", "Read", "ReadWrite")
            try {
                $len = [int64]$fs.Length
                $take = [int][Math]::Min(2000000L, $len)
                [void]$fs.Seek($len - $take, "Begin")
                $buf = New-Object byte[] $take
                [void]$fs.Read($buf, 0, $buf.Length)
            }
            finally {
                $fs.Close()
            }
            $text = [System.Text.Encoding]::UTF8.GetString($buf).Replace(([string][char]0), "")
            $remain = Find-Remain $text $boxKey
            if ($remain) { break }
        }
        if (-not $remain) { Start-Sleep -Milliseconds 200 }
    }
    if (-not $remain) { $remain = "未能读出" }
    Write-Left $remain
}
catch {
    Write-Left "未能读出"
}
exit 0

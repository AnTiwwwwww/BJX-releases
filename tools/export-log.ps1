# 把当前日志和报错截图复制到 export 目录，并打开那个文件夹。
param([switch] $NoOpen)

$ErrorActionPreference = "Continue"

$root = Split-Path $PSScriptRoot -Parent
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$dest = Join-Path $root "export\BJX-$stamp"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$debug = Join-Path $root "debug"
$copied = 0
if (Test-Path -LiteralPath $debug) {
    Get-ChildItem -LiteralPath $debug -File | Where-Object {
        $_.Name -notlike "maafw.bak.*" -and ($_.Extension -in ".log", ".txt")
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
        $copied++
    }
    $shots = Join-Path $debug "on_error"
    if (Test-Path -LiteralPath $shots) {
        $shotDest = Join-Path $dest "on_error"
        New-Item -ItemType Directory -Force -Path $shotDest | Out-Null
        Get-ChildItem -LiteralPath $shots -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $shotDest $_.Name) -Force
            $copied++
        }
    }
}

if (-not $NoOpen) {
    Add-Type -AssemblyName System.Windows.Forms
    Start-Process -FilePath "explorer.exe" -ArgumentList ('"' + $dest + '"') | Out-Null
    [System.Windows.Forms.MessageBox]::Show(
        "已导出 $copied 个文件。`n$dest",
        "BJX",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button1,
        [System.Windows.Forms.MessageBoxOptions]::DefaultDesktopOnly) | Out-Null
}
Write-Output $dest
exit 0

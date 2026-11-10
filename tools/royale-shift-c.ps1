# mark 只记下本局时间；check 由确认局内画面的流水线同步调用。
# 不创建延时进程：任务停止、回到主城或进入结算后，不会再自行按键。
param(
    [Parameter(Position = 0)]
    [string] $Mode = "mark",
    [Parameter(Position = 1)]
    [string] $Token = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bjx-log.ps1")
$path = Join-Path (Split-Path $PSScriptRoot -Parent) 'debug/royale-shift-c.txt'
$dir = Split-Path -Parent $path
if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
}

function Write-State([string] $Id, [long] $Start, [int] $Pressed) {
    $line = "{0} {1} {2}" -f $Id, $Start, $Pressed
    [System.IO.File]::WriteAllText($path, $line, [System.Text.UTF8Encoding]::new($false))
}

function Read-State {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $parts = ([System.IO.File]::ReadAllText($path)).Trim() -split "\s+"
    if ($parts.Length -lt 3) { return $null }
    return [pscustomobject]@{
        Id      = $parts[0]
        Start   = [long]$parts[1]
        Pressed = [int]$parts[2]
    }
}

if ($Mode -eq "mark") {
    $id = [guid]::NewGuid().ToString("n")
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    Write-State $id $now 0
    Write-BjxLog "吃鸡 记下进局 $id，仅在任务确认局内时检查十分钟 Shift+C"
    exit 0
}

# 保留旧调用参数，旧 wait 模式立即退出。
if ($Mode -ne "check") { exit 0 }
$state = Read-State
if (-not $state -or $state.Pressed -ne 0) { exit 0 }
$elapsed = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $state.Start
if ($elapsed -lt 600000) { exit 0 }

if (-not ("BjxKeys" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class BjxKeys {
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    public static void ShiftC() {
        const uint up = 2;
        try {
            keybd_event(0xA0, 0, 0, UIntPtr.Zero);
            System.Threading.Thread.Sleep(40);
            keybd_event(0x43, 0, 0, UIntPtr.Zero);
            System.Threading.Thread.Sleep(40);
        }
        finally {
            keybd_event(0x43, 0, up, UIntPtr.Zero);
            keybd_event(0xA0, 0, up, UIntPtr.Zero);
        }
    }
    public static bool GameIsForeground() {
        var sb = new StringBuilder(256);
        GetClassName(GetForegroundWindow(), sb, sb.Capacity);
        return sb.ToString() == "KGWin32App";
    }
}
"@
}

if (-not [BjxKeys]::GameIsForeground()) {
    Write-BjxLog "吃鸡 Shift+C 跳过：游戏不在前台"
    exit 0
}
Write-State $state.Id $state.Start 1
[BjxKeys]::ShiftC()
Write-BjxLog "吃鸡 按下 Shift+C"
exit 0

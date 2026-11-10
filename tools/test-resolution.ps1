# 用隔离的窗口状态运行实际启动检查，不操作游戏，也不显示提醒。
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sandboxRoot = Join-Path $projectRoot ('debug/resolution-test/' + [guid]::NewGuid().ToString('n'))
$sandboxTools = Join-Path $sandboxRoot 'tools'
New-Item -ItemType Directory -Path $sandboxTools -Force | Out-Null
$script = Join-Path $sandboxTools 'remind-resolution.ps1'
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'remind-resolution.ps1') -Raw
$source = [regex]::Replace($source, '(?s)function Show-Remind\b.*?\r?\n}', "function Show-Remind { throw 'BJX_CAPTURE_NOT_READY' }")
Set-Content -LiteralPath $script -Value $source -Encoding utf8
Set-Content -LiteralPath (Join-Path $sandboxTools 'bjx-log.ps1') -Value 'function Write-BjxLog([string] $Message) { }' -Encoding utf8

Add-Type @'
using System;
public static class BjxWindow {
    public static bool Minimized;
    public static bool Foreground;
    public static bool PseudoMinimized;
    public static bool ActivationAllowed = true;
    public static IntPtr FindGame() { return new IntPtr(1); }
    public static bool IsMinimized(IntPtr handle) { return Minimized; }
    public static bool IsForeground(IntPtr handle) { return Foreground; }
    public static string Title(IntPtr handle) { return "BJX test window"; }
    public static string ClientSize(IntPtr handle, out int width, out int height) {
        width = 1920;
        height = 1080;
        return "1920×1080";
    }
    public static void OpenMinimized(IntPtr handle) {
        if (!Minimized) return;
        OpenForCapture(handle);
    }
    public static void OpenForCapture(IntPtr handle) {
        if (!ActivationAllowed) return;
        Minimized = false;
        Foreground = true;
        // MaaFramework 在窗口激活后恢复伪最小化时的样式和透明度。
        PseudoMinimized = false;
    }
}
'@

foreach ($case in @(
    @{ Name = '正常前台窗口'; Minimized = $false; Foreground = $true; Pseudo = $false },
    @{ Name = '真正最小化的窗口'; Minimized = $true; Foreground = $false; Pseudo = $false },
    @{ Name = '透明还原的伪最小化窗口'; Minimized = $false; Foreground = $false; Pseudo = $true }
)) {
    [BjxWindow]::Minimized = $case.Minimized
    [BjxWindow]::Foreground = $case.Foreground
    [BjxWindow]::PseudoMinimized = $case.Pseudo
    & $script '单人吃鸡刷币'
    if ([BjxWindow]::Minimized -or [BjxWindow]::PseudoMinimized -or -not [BjxWindow]::Foreground) {
        throw "FAIL: $($case.Name)已通过启动检查，但尚未恢复到可截图的前台状态"
    }
    Write-Output "PASS: $($case.Name)在启动检查通过前已恢复到前台"
}

[BjxWindow]::Minimized = $false
[BjxWindow]::Foreground = $false
[BjxWindow]::PseudoMinimized = $true
[BjxWindow]::ActivationAllowed = $false
$blocked = $false
try {
    & $script '单人吃鸡刷币'
}
catch {
    if ($_.Exception.Message -ne 'BJX_CAPTURE_NOT_READY') { throw }
    $blocked = $true
}
if (-not $blocked) { throw 'FAIL: 激活失败时不能仅凭尺寸正确放行' }
Write-Output 'PASS: 激活失败时保持在提醒处，不继续识别或操作'

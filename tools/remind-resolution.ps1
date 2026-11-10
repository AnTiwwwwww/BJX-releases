# 任务开始前先还原并激活无界，解除截图引擎的伪最小化，再量客户区。
# 已经是窗口模式 1920×1080 就直接继续，不弹窗。
# 还最小化，或尺寸不对，就停在提醒上，不往下点。取消后也不往下点，等 MXU 里停止。
param(
    [Parameter(Position = 0)]
    [string] $Task = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "bjx-log.ps1")
Add-Type -AssemblyName System.Windows.Forms

if (-not ("BjxWindow" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class BjxWindow {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    static IntPtr found;
    public static IntPtr FindGame() {
        found = IntPtr.Zero;
        EnumWindows((h, l) => {
            if (!IsWindowVisible(h) && !IsIconic(h)) return true;
            var cls = new StringBuilder(256);
            GetClassName(h, cls, cls.Capacity);
            if (cls.ToString() != "KGWin32App") return true;
            var title = new StringBuilder(512);
            GetWindowText(h, title, title.Capacity);
            var text = title.ToString();
            if (text.IndexOf("grok", StringComparison.OrdinalIgnoreCase) >= 0) return true;
            if (!text.Contains("剑网3")) return true;
            found = h;
            return false;
        }, IntPtr.Zero);
        return found;
    }
    public static bool IsMinimized(IntPtr hWnd) {
        return hWnd != IntPtr.Zero && IsIconic(hWnd);
    }
    public static string Title(IntPtr hWnd) {
        var title = new StringBuilder(512);
        GetWindowText(hWnd, title, title.Capacity);
        return title.ToString();
    }
    public static bool IsForeground(IntPtr hWnd) {
        return hWnd != IntPtr.Zero && GetForegroundWindow() == hWnd;
    }
    public static void OpenForCapture(IntPtr hWnd) {
        if (IsMinimized(hWnd)) ShowWindow(hWnd, 9);
        SetForegroundWindow(hWnd);
    }
    public static string ClientSize(IntPtr hWnd, out int width, out int height) {
        width = 0;
        height = 0;
        RECT rect;
        if (!GetClientRect(hWnd, out rect)) return "没量到客户区";
        width = rect.Right - rect.Left;
        height = rect.Bottom - rect.Top;
        return width.ToString() + "×" + height.ToString();
    }
}
"@
}

function Show-Remind([string] $Text, [System.Windows.Forms.MessageBoxButtons] $Buttons) {
    return [System.Windows.Forms.MessageBox]::Show(
        $Text,
        "BJX",
        $Buttons,
        [System.Windows.Forms.MessageBoxIcon]::Information,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button1,
        [System.Windows.Forms.MessageBoxOptions]::DefaultDesktopOnly)
}

$taskName = if ([string]::IsNullOrWhiteSpace($Task)) { "任务" } else { $Task }

while ($true) {
    $hwnd = [BjxWindow]::FindGame()
    $width = 0
    $height = 0
    if ($hwnd -eq [IntPtr]::Zero) {
        $size = "没找到剑网3无界窗口"
        $ready = $false
        Write-BjxLog "$taskName 分辨率：没找到剑网3无界窗口"
    }
    else {
        if ([BjxWindow]::IsMinimized($hwnd)) {
            Write-BjxLog "$taskName 分辨率：窗口最小化，先还原无界 hwnd=$hwnd title=$([BjxWindow]::Title($hwnd))"
        }
        elseif (-not [BjxWindow]::IsForeground($hwnd)) {
            Write-BjxLog "$taskName 分辨率：先激活无界，恢复截图画面 hwnd=$hwnd"
        }
        [BjxWindow]::OpenForCapture($hwnd)
        # 伪最小化后 IsIconic 已为 false，激活后等截图引擎恢复样式和透明度。
        Start-Sleep -Milliseconds 800
        if ([BjxWindow]::IsMinimized($hwnd)) {
            $size = "无界窗口还是最小化"
            $ready = $false
            Write-BjxLog "$taskName 分辨率：还原后仍是最小化 hwnd=$hwnd"
        }
        elseif (-not [BjxWindow]::IsForeground($hwnd)) {
            $size = "无界窗口未能激活，请先切到游戏后重试"
            $ready = $false
            Write-BjxLog "$taskName 分辨率：激活前台失败 hwnd=$hwnd"
        }
        else {
            $size = [BjxWindow]::ClientSize($hwnd, [ref] $width, [ref] $height)
            $ready = ($width -eq 1920 -and $height -eq 1080)
            if ($ready) {
                Write-BjxLog "$taskName 分辨率：客户区 $size，继续 hwnd=$hwnd"
            }
            else {
                Write-BjxLog "$taskName 分辨率：客户区 $size，等待修改 hwnd=$hwnd"
            }
        }
    }

    if ($ready) { exit 0 }

    $choice = Show-Remind "BJX 只做一套分辨率识别。`n请把游戏改成窗口模式，客户区 1920×1080，界面缩放 100%。`n`n当前：$size`n`n改好后点重试。" ([System.Windows.Forms.MessageBoxButtons]::RetryCancel)
    if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) {
        Show-Remind "已取消。这次不会点游戏。请在 MXU 里停止本次任务。" ([System.Windows.Forms.MessageBoxButtons]::OK) | Out-Null
        Start-Sleep -Seconds 86400
        exit 0
    }
}

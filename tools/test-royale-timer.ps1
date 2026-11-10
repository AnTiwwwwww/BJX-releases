# 在隔离目录里运行实际计时脚本；替换按键类，禁止启动延时子进程。
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sandboxRoot = Join-Path $projectRoot ('debug/royale-timer-test/' + [guid]::NewGuid().ToString('n'))
$sandboxTools = Join-Path $sandboxRoot 'tools'
$stateFile = Join-Path $sandboxRoot 'debug/royale-shift-c.txt'
New-Item -ItemType Directory -Path $sandboxTools -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $stateFile -Parent) -Force | Out-Null
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'royale-shift-c.ps1') -Raw
$script = Join-Path $sandboxTools 'royale-shift-c.ps1'
Set-Content -LiteralPath $script -Value $source -Encoding utf8
Set-Content -LiteralPath (Join-Path $sandboxTools 'bjx-log.ps1') -Value 'function Write-BjxLog([string] $Message) { }' -Encoding utf8

function Invoke-CimMethod {
    throw 'FAIL: mark 启动了脱离任务的延时子进程，任务结束后仍可能按键'
}

Add-Type @'
public static class BjxKeys {
    public static bool Foreground = true;
    public static int PressCount = 0;
    public static bool GameIsForeground() { return Foreground; }
    public static void ShiftC() { PressCount++; }
}
'@

function Assert-Equal($Actual, $Expected, [string] $Message) {
    if ($Actual -ne $Expected) { throw "FAIL: $Message (actual=$Actual, expected=$Expected)" }
}

& $script mark
Assert-Equal (Test-Path -LiteralPath $stateFile) $true 'mark 应记录本局时间'
Assert-Equal ([BjxKeys]::PressCount) 0 '进局时不能立刻按 Shift+C'
$state = (Get-Content -LiteralPath $stateFile -Raw).Trim() -split '\s+'
$past = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 601000
Set-Content -LiteralPath $stateFile -Value "$($state[0]) $past 0" -Encoding utf8
& $script check
Assert-Equal ([BjxKeys]::PressCount) 1 '超过十分钟、游戏在前台时应按一次'
& $script check
Assert-Equal ([BjxKeys]::PressCount) 1 '同一局不能重复按'

& $script mark
& $script check
Assert-Equal ([BjxKeys]::PressCount) 1 '下一局应重新计时'
$state = (Get-Content -LiteralPath $stateFile -Raw).Trim() -split '\s+'
Set-Content -LiteralPath $stateFile -Value "$($state[0]) $past 0" -Encoding utf8
[BjxKeys]::Foreground = $false
& $script check
Assert-Equal ([BjxKeys]::PressCount) 1 '游戏不在前台时不能给其他窗口按键'
[BjxKeys]::Foreground = $true
& $script check
Assert-Equal ([BjxKeys]::PressCount) 2 '回到前台后可补按一次'
& $script wait 'legacy-token'
Assert-Equal ([BjxKeys]::PressCount) 2 '旧 wait 模式不能再延时按键'
Write-Output 'PASS: 无延时子进程；十分钟后按一次；新局重计时；非前台不按；旧 wait 不按'

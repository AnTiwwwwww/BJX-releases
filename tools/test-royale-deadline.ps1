param([string] $AssemblyPath)

# 固定本机时间，验证实际 Agent 的日期计算，不启动游戏或等待到凌晨。
$ErrorActionPreference = 'Stop'
if ($AssemblyPath) {
    $assembly = [Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $AssemblyPath).Path)
    $clockType = $assembly.GetType('RoyaleClock', $true)
} else {
    $clockType = Add-Type -Path @((Join-Path $PSScriptRoot 'bjx-royale-clock.cs'), (Join-Path $PSScriptRoot 'bjx-powershell.cs')) -PassThru |
        Where-Object Name -EQ 'RoyaleClock'
}
$method = $clockType.GetMethod('NextDeadline', [Reflection.BindingFlags]'Static,NonPublic')
$cases = @(
    @('2026-11-10 00:00:00', '01:30', '2026-11-11 01:30:00'),
    @('2026-11-10 00:15:00', '01:30', '2026-11-11 01:30:00'),
    @('2026-11-10 01:29:59', '01:30', '2026-11-11 01:30:00'),
    @('2026-11-10 01:30:00', '01:30', '2026-11-11 01:30:00'),
    @('2026-11-10 08:00:00', '01:30', '2026-11-11 01:30:00'),
    @('2026-11-10 23:59:59', '01:30', '2026-11-11 01:30:00'),
    @('2026-11-30 00:15:00', '01:30', '2026-12-01 01:30:00'),
    @('2026-12-31 00:15:00', '01:30', '2027-01-01 01:30:00'),
    @('2028-02-28 00:15:00', '01:30', '2028-02-29 01:30:00'),
    @('2026-11-10 08:00:00', '18:45', '2026-11-11 18:45:00')
)
$failures = 0
foreach ($case in $cases) {
    $localNow = [DateTime]::ParseExact($case[0], 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
    $time = [TimeSpan]::ParseExact($case[1], 'hh\:mm', [Globalization.CultureInfo]::InvariantCulture)
    $actual = $method.Invoke($null, @($localNow, $time)).ToString('yyyy-MM-dd HH:mm:ss')
    if ($actual -ne $case[2]) {
        Write-Output "FAIL: start=$($case[0]), cutoff=$($case[1]), actual=$actual, expected=$($case[2])"
        $failures++
    }
}
if ($failures) { throw "$failures / $($cases.Count) 个次日截止时间用例失败" }
Write-Output "PASS: $($cases.Count) 个次日截止时间用例（凌晨、恰好到点、白天、月末、年末、闰日、自定义时间）"

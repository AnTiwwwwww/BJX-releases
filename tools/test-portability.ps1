# 在含中文、空格和方括号的临时目录中运行真实脚本；配置为空，不发送通知或邮件。
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$sandbox = Join-Path $tempRoot ('BJX 路径测试 [' + [guid]::NewGuid().ToString('n') + ']')
$testTools = Join-Path $sandbox 'tools'
foreach ($relative in @('tools', 'debug/on_error', 'config', 'unrelated')) {
    New-Item -ItemType Directory -Path (Join-Path $sandbox $relative) -Force | Out-Null
}
function Assert-True([bool] $Value, [string] $Message) {
    if (-not $Value) { throw "FAIL: $Message" }
}
try {
    foreach ($name in @('bjx-log.ps1', 'record-royale-left.ps1', 'send-royale-mail.ps1', 'notify-wecom.ps1', 'export-log.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $testTools $name)
    }
    Set-Content -LiteralPath (Join-Path $sandbox 'config/royale-mail.local.json') -Value '{}' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $sandbox 'config/wecom-webhook.local.json') -Value '{}' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $sandbox 'accounts.csv') -Value 'test-only-private-data' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $sandbox 'debug/maafw.log') -Value '{"box":[1,2,3,4],"text":"82"}' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $sandbox 'debug/on_error/sample.txt') -Value 'test-only-capture' -Encoding utf8
    Push-Location -LiteralPath (Join-Path $sandbox 'unrelated')
    try {
        . (Join-Path $testTools 'bjx-log.ps1')
        Write-BjxLog 'portability-test'
        Assert-True (Test-Path -LiteralPath (Join-Path $sandbox 'debug/bjx.log')) '日志应写到脚本所属项目'
        & (Join-Path $testTools 'record-royale-left.ps1') '' '[1,2,3,4]' | Out-Null
        $leftFile = Join-Path $sandbox 'debug/royale-weekly-left.txt'
        Assert-True ((Get-Content -LiteralPath $leftFile -Raw) -match '\s82\s*$') '额度应从此项目的日志读取并保存'
        Set-Content -LiteralPath $leftFile -Value @('2026-11-10 14:00:00  82', '2026-11-10 14:10:00  60') -Encoding utf8
        . (Join-Path $testTools 'send-royale-mail.ps1')
        Assert-True ((Get-PreviousNumber) -eq '82') '邮件变化值应读取此项目的上一条记录'
        Add-MailLog 'portability-test'
        Assert-True (Test-Path -LiteralPath (Join-Path $sandbox 'debug/royale-mail.log')) '邮件日志应留在此项目'
        & (Join-Path $testTools 'notify-wecom.ps1') 'test' 'ok' | Out-Null
        $exported = & (Join-Path $testTools 'export-log.ps1') -NoOpen
        Assert-True ($exported.StartsWith((Join-Path $sandbox 'export'), [StringComparison]::OrdinalIgnoreCase)) '导出位置应在此项目内'
        Assert-True (Test-Path -LiteralPath (Join-Path $exported 'bjx.log')) '导出应包含此项目日志'
        Assert-True (Test-Path -LiteralPath (Join-Path $exported 'on_error/sample.txt')) '导出应包含本地错误样本'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $exported 'accounts.csv'))) '日志导出不得包含账号表'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $exported 'config'))) '日志导出不得包含通知配置'
    } finally { Pop-Location }

    & (Join-Path $PSScriptRoot 'build.ps1') -OutputDirectory $testTools | Out-Null
    $probe = Join-Path $sandbox '参数检查.ps1'
    $probeResult = Join-Path $sandbox 'arguments.json'
    Set-Content -LiteralPath $probe -Encoding utf8 -Value @'
param([string] $OutFile, [Parameter(ValueFromRemainingArguments)] [string[]] $Values)
ConvertTo-Json -InputObject @($Values) -Compress | Set-Content -LiteralPath $OutFile -Encoding utf8
exit 17
'@
    $values = @('中文 带空格', 'a"b', 'literal$(safe)', '', 'trailing slash\')
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $testTools 'bjx-run.exe'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    foreach ($value in (@('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $probe, $probeResult) + $values)) {
        $start.ArgumentList.Add($value)
    }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $process.WaitForExit()
        Assert-True ($process.ExitCode -eq 17) '启动器应保留子进程退出码'
    } finally { $process.Dispose() }
    $received = @(Get-Content -LiteralPath $probeResult -Raw | ConvertFrom-Json)
    Assert-True ($received.Count -eq $values.Count) '启动器不得丢失空参数'
    for ($i = 0; $i -lt $values.Count; $i++) {
        Assert-True ($received[$i] -ceq $values[$i]) "启动器参数 $i 应保持原样"
    }
    Write-Output 'PASS: 异地中文/空格/方括号目录、无关工作目录、日志/额度/邮件/导出、本地资料排除、两个 EXE 构建、启动器参数与退出码'
} finally {
    $resolved = [IO.Path]::GetFullPath($sandbox)
    if (-not $resolved.StartsWith($tempRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolved -Leaf) -notlike 'BJX 路径测试 *') { throw '临时目录边界检查失败，未清理' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

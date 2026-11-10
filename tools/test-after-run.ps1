# 回放 MXU 队列状态，替换退出、窗口关闭和关机的实际调用。
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sandbox = Join-Path $root ('debug/after-run-test/' + [guid]::NewGuid().ToString('n'))
$testTools = Join-Path $sandbox 'tools'
$testConfig = Join-Path $sandbox 'config'
New-Item -ItemType Directory -Path $testTools, $testConfig | Out-Null

$testScript = Join-Path $testTools 'after-run.ps1'
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'after-run.ps1') -Raw
$shutdownCommand = '& $shutdown /s /t 0'
if (-not $source.Contains($shutdownCommand)) { throw '无法替换真实关机命令' }
$testShutdown = @'
Invoke-TestShutdown
            $LASTEXITCODE = 0
'@
Set-Content -LiteralPath $testScript -Value $source.Replace($shutdownCommand, $testShutdown) -Encoding utf8
Set-Content -LiteralPath (Join-Path $testTools 'bjx-log.ps1') -Value 'function Write-BjxLog([string] $Message) { }' -Encoding utf8
Set-Content -LiteralPath (Join-Path $testConfig 'mxu-BJX.json') -Encoding utf8 -Value @'
{"instances":[{"id":"test","tasks":[{"id":"end","taskName":"运行结束后操作"}]}],"settings":{"webServerPort":12701}}
'@

$effects = [System.Collections.Generic.List[string]]::new()
$queue = @{
    overall_status = 'Running'
    pending_task_ids = @(200000001, 200000002)
    current_task_index = 1
    mappings = @{ '200000001' = 'royale'; '200000002' = 'end' }
    statuses = @{ royale = 'succeeded'; end = 'running' }
}
$states = @{ test = @{ is_running = $true; task_run_state = $queue } }
$windowCount = 1

function Get-CimInstance($ClassName, $Filter) {
    switch ($Filter) {
        "ProcessId=$PID" { return @{ ParentProcessId = 1001 } }
        'ProcessId=1001' { return @{ ParentProcessId = 1002; ExecutablePath = (Join-Path $testTools 'bjx-run.exe') } }
        'ProcessId=1002' { return @{ ProcessId = 1002; SessionId = 1; ExecutablePath = (Join-Path $sandbox 'mxu.exe') } }
    }
    throw "Unexpected process lookup: $Filter"
}
function Get-NetTCPConnection($OwningProcess, $State, $ErrorAction) {
    if ($OwningProcess -ne 1002 -or $State -ne 'Listen') { throw '查询了错误的服务进程' }
    return @{ LocalPort = 12703; LocalAddress = '127.0.0.1' }
}
function Invoke-WebRequest($Uri, [switch] $NoProxy, $TimeoutSec) {
    if ($Uri -ne 'http://127.0.0.1:12703/api/maa/state' -or -not $NoProxy) { throw '查询了错误的状态接口' }
    return @{ Content = (@{ instances = $states } | ConvertTo-Json -Depth 12) }
}
function Invoke-RestMethod($Uri, $Method, $ContentType, $Body, [switch] $NoProxy, $TimeoutSec) {
    if ($Method -ne 'Post' -or $Uri -ne 'http://127.0.0.1:12703/api/maa/instances/test/tasks/200000002/pipeline') {
        throw '退出节点应只对当前任务启用'
    }
    $override = ($Body | ConvertFrom-Json).pipeline_override | ConvertFrom-Json -AsHashtable
    if ($override['结束后关闭BJX'].enabled -ne $true) { throw '退出节点未启用' }
    $effects.Add('close-bjx')
    return @{ success = $true }
}
function Get-Process($Name, $ErrorAction) {
    if ($Name -ne 'JX3ClientX3DX64') { throw '查询了错误的游戏进程' }
    $window = [pscustomobject]@{ SessionId = 1; MainWindowHandle = 12; MainWindowTitle = '剑网3无界测试窗口' }
    $requests = $effects
    $window | Add-Member -MemberType ScriptMethod -Name CloseMainWindow -Value ({
        $requests.Add('close-game')
        return $true
    }.GetNewClosure())
    for ($i = 0; $i -lt $windowCount; $i++) { $window }
}
function Invoke-TestShutdown { $effects.Add('shutdown') }

function Assert-Effect($Operation, $Expected) {
    $effects.Clear()
    $output = & $testScript $Operation 3>&1
    if (($effects -join ',') -ne $Expected) {
        throw "操作 $Operation 的实际调用为 $($effects -join ',')，预期为 $Expected。$output"
    }
}

Assert-Effect 'none' ''
foreach ($operation in 'close-bjx', 'close-game', 'shutdown') {
    Assert-Effect $operation $operation
}
Write-Output 'PASS: 默认无操作，成功队列分别派发关闭 BJX、关闭无界和正常关机'

$queue.statuses.royale = 'failed'
Assert-Effect 'shutdown' ''
$queue.statuses.royale = 'succeeded'
$queue.current_task_index = 0
Assert-Effect 'close-bjx' ''
$queue.current_task_index = 1
$states.test.is_running = $false
Assert-Effect 'shutdown' ''
$states.test.is_running = $true
$states.other = @{ is_running = $true }
Assert-Effect 'close-bjx' ''
$states.Remove('other')
$windowCount = 2
Assert-Effect 'close-game' ''
Write-Output 'PASS: 前项失败、顺序不对、任务已停止、其他实例运行或窗口有歧义时跳过操作'

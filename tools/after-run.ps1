param(
    [ValidateSet('none', 'close-bjx', 'close-game', 'shutdown')]
    [string] $Operation = 'none'
)

function Get-BjxCompletionContext($Instances, $Config) {
    $running = @($Instances.GetEnumerator() | Where-Object { $_.Value.is_running })
    if ($running.Count -ne 1) {
        throw '需要且只能有一个 BJX 运行实例执行结束后操作'
    }

    $instance = $running[0]
    $run = $instance.Value.task_run_state
    $queue = @($run.pending_task_ids)
    if ($run.overall_status -ne 'Running' -or $queue.Count -lt 2 -or
        $run.current_task_index -ne ($queue.Count - 1)) {
        throw '请把运行结束后操作放在已勾选任务的最后，并至少勾选一个前置任务'
    }

    $taskId = $queue[-1]
    $selectedId = $run.mappings[[string] $taskId]
    $saved = $Config.instances | Where-Object { $_.id -eq $instance.Key }
    $selected = $saved.tasks | Where-Object { $_.id -eq $selectedId }
    if ($selected.taskName -ne '运行结束后操作' -or $run.statuses[$selectedId] -ne 'running') {
        throw '当前任务已不在结束后操作节点'
    }

    foreach ($previousId in $queue[0..($queue.Count - 2)]) {
        $previous = $run.mappings[[string] $previousId]
        if (-not $previous -or $run.statuses[$previous] -ne 'succeeded') {
            throw '前面的任务未全部成功结束'
        }
    }

    return @{ InstanceId = $instance.Key; TaskId = $taskId }
}

if ($Operation -eq 'none') { return }

$ErrorActionPreference = 'Stop'
$toolsDir = [IO.Path]::GetFullPath($PSScriptRoot)
. (Join-Path $toolsDir 'bjx-log.ps1')
$project = Split-Path $toolsDir -Parent

try {
    $configPath = Join-Path $project 'config/mxu-BJX.json'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable

    # 只向启动本脚本的 BJX 请求队列状态，避免误用同一台电脑上的其他 MXU。
    $scriptProcess = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$PID"
    $launcher = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$($scriptProcess.ParentProcessId)"
    $mxu = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$($launcher.ParentProcessId)"
    if ($launcher.ExecutablePath -ne (Join-Path $toolsDir 'bjx-run.exe') -or
        $mxu.ExecutablePath -ne (Join-Path $project 'mxu.exe')) {
        throw '无法确认启动本操作的 BJX 进程'
    }

    $port = [int] ($config.settings.webServerPort ?? 12701)
    $ports = $port..([Math]::Min(65535, $port + 9))
    $listeners = @(Get-NetTCPConnection -OwningProcess $mxu.ProcessId -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -in $ports -and $_.LocalAddress -in @('127.0.0.1', '0.0.0.0') } |
        Select-Object -ExpandProperty LocalPort -Unique)
    if ($listeners.Count -ne 1) {
        throw '无法连接 BJX 的 MXU 本机 Web 服务'
    }

    $api = "http://127.0.0.1:$($listeners[0])/api/maa"
    $state = (Invoke-WebRequest -Uri "$api/state" -NoProxy -TimeoutSec 3).Content |
        ConvertFrom-Json -AsHashtable
    $context = Get-BjxCompletionContext $state.instances $config

    switch ($Operation) {
        'close-bjx' {
            # Command 动作不会检查外部进程退出码。仅在队列检查通过后，为本次任务启用 MXU 的正常退出节点。
            $pipeline = @{ '结束后关闭BJX' = @{ enabled = $true } } | ConvertTo-Json -Compress
            $body = @{ pipeline_override = $pipeline } | ConvertTo-Json -Compress
            $instanceId = [Uri]::EscapeDataString($context.InstanceId)
            $result = Invoke-RestMethod -Uri "$api/instances/$instanceId/tasks/$($context.TaskId)/pipeline" `
                -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -NoProxy -TimeoutSec 3
            if ($result.success -ne $true) { throw 'MXU 未接受关闭 BJX 的请求' }
            Write-BjxLog '运行结束后操作 已请求关闭 BJX'
        }
        'close-game' {
            $windows = @(Get-Process -Name 'JX3ClientX3DX64' -ErrorAction SilentlyContinue | Where-Object {
                $_.SessionId -eq $mxu.SessionId -and $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like '*剑网3*'
            })
            if ($windows.Count -ne 1) { throw '无法唯一确定当前会话的无界窗口' }
            if (-not $windows[0].CloseMainWindow()) { throw '无界窗口未接受关闭请求' }
            Write-BjxLog '运行结束后操作 已向无界发送正常关闭请求'
        }
        'shutdown' {
            $shutdown = Join-Path ([Environment]::SystemDirectory) 'shutdown.exe'
            & $shutdown /s /t 0
            if ($LASTEXITCODE -ne 0) { throw "Windows 关机请求失败，退出码 $LASTEXITCODE" }
            Write-BjxLog '运行结束后操作 已请求 Windows 正常关机'
        }
    }
}
catch {
    Write-BjxLog "运行结束后操作 跳过：$($_.Exception.Message)"
    Write-Warning $_.Exception.Message
}

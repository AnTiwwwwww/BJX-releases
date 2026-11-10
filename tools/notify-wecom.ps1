# 任务结束时给企业微信群机器人发一条文字。
# 地址只读 config/wecom-webhook.local.json。这个脚本不写密钥。
# 找不到配置、或请求失败，都退出 0，避免把已经做完的任务判失败。
param(
    [Parameter(Position = 0)]
    [string] $Task = "任务",
    [Parameter(Position = 1)]
    [string] $Result = "ok"
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "bjx-log.ps1")
Write-BjxLog "任务结果 $Task $Result"

function Find-WebhookConfig {
    $dir = $PSScriptRoot
    for ($i = 0; $i -lt 6 -and $dir; $i++) {
        $candidate = Join-Path $dir "config\wecom-webhook.local.json"
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) {
            break
        }
        $dir = $parent
    }
    return $null
}

try {
    $configPath = Find-WebhookConfig
    if (-not $configPath) {
        Write-Output "notify skipped: no config"
        exit 0
    }

    $cfg = Get-Content -LiteralPath $configPath -Raw -Encoding utf8 | ConvertFrom-Json
    $url = [string]$cfg.url
    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-Output "notify skipped: empty url"
        exit 0
    }

    $label = switch ($Result) {
        "ok" { "完成" }
        "skip" { "跳过" }
        "stop" { "停掉" }
        default { "完成" }
    }

    $name = ($Task -replace "[\r\n]", " ").Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "任务"
    }
    if ($name.Length -gt 64) {
        $name = $name.Substring(0, 64)
    }

    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $content = "BJX $name $label $now"
    $body = @{
        msgtype = "text"
        text    = @{ content = $content }
    } | ConvertTo-Json -Compress -Depth 4

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("bjx-wecom-" + [guid]::NewGuid().ToString("n") + ".json")
    [System.IO.File]::WriteAllText($tmp, $body, [System.Text.UTF8Encoding]::new($false))
    try {
        $response = & curl.exe -sS --max-time 15 -H "Content-Type: application/json; charset=utf-8" --data-binary "@$tmp" $url 2>$null
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }

    $errcode = "?"
    if ($response) {
        try {
            $parsed = ($response | Out-String).Trim() | ConvertFrom-Json
            $errcode = [string]$parsed.errcode
        }
        catch {
            $errcode = "unparsed"
        }
    }
    Write-Output "notify errcode=$errcode"
}
catch {
    Write-Output "notify failed"
}

exit 0

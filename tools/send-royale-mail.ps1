# 把飞沙令剩余发到本地配置里的邮箱。
# 配置在 config/royale-mail.local.json，这个目录不上传。
# 没有授权码或发送失败都退出 0，不打断排队。
param(
    [Parameter(Position = 0)]
    [string] $Line = ""
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "bjx-log.ps1")

function Add-MailLog([string] $Message) {
    try {
        $dir = Join-Path (Split-Path $PSScriptRoot -Parent) "debug"
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir | Out-Null
        }
        $path = Join-Path $dir "royale-mail.log"
        $row = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
        [System.IO.File]::AppendAllText($path, $row + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        Write-BjxLog "飞沙令邮件 $Message"
    }
    catch {
    }
}

function Find-MailConfig {
    $dir = $PSScriptRoot
    for ($i = 0; $i -lt 6 -and $dir; $i++) {
        $candidate = Join-Path $dir "config\royale-mail.local.json"
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Encode-Html([string] $Text) {
    if ($null -eq $Text) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Get-RemainPoints([string] $Text) {
    $points = @()
    $regex = [regex]'((?:\d{4}-\d{2}-\d{2}\s+)?\d{1,2}:\d{2}(?::\d{2})?)\s+(未能读出|\d{1,5})'
    foreach ($m in $regex.Matches($Text)) {
        $points += [pscustomobject]@{
            Time   = $m.Groups[1].Value
            Remain = $m.Groups[2].Value
        }
    }
    return @($points)
}

function Get-Clock([string] $Time) {
    if ($Time -match '(\d{1,2}:\d{2})(?::\d{2})?\s*$') { return $Matches[1] }
    return $Time
}

function Get-ChangeText($Previous, $Current) {
    if ($Previous -notmatch '^\d+$' -or $Current -notmatch '^\d+$') { return "" }
    $delta = [int]$Current - [int]$Previous
    if ($delta -eq 0) { return "持平" }
    if ($delta -lt 0) { return ("少 " + (-$delta)) }
    return ("多 " + $delta)
}

function Get-MailBody([string] $Text) {
    $points = @(Get-RemainPoints $Text)
    if ($points.Count -eq 0) {
        $safe = Encode-Html $Text
        return "<div style=`"font-family:'Microsoft YaHei',sans-serif;font-size:16px;line-height:1.7;color:#222;background:#fff`">$safe</div>"
    }

    $latest = $points[$points.Count - 1]
    $date = ""
    if ($points[0].Time -match '^(\d{4}-\d{2}-\d{2})') { $date = $Matches[1] }
    $summary = ""
    $numbers = @($points | Where-Object { $_.Remain -match '^\d+$' })
    if ($numbers.Count -ge 2) {
        $first = [int]$numbers[0].Remain
        $last = [int]$numbers[$numbers.Count - 1].Remain
        $used = $first - $last
        $change = if ($used -gt 0) { "少了 $used" } elseif ($used -lt 0) { "多了 $([Math]::Abs($used))" } else { "没有变化" }
        $when = if ($date) { "{0}，" -f $date } else { "" }
        $summary = "{0}共 {1} 次，从 {2} 到 {3}，{4}。" -f $when, $points.Count, $first, $last, $change
    }
    elseif ($points.Count -eq 1) {
        $clock = Get-Clock $latest.Time
        $when = if ($date) { "$date $clock" } else { $clock }
        $summary = "$when 还剩 $($latest.Remain)。"
        $previous = Get-PreviousNumber
        $change = Get-ChangeText $previous $latest.Remain
        if ($change -eq "持平") { $summary = "{0} 还剩 {1}，与上条持平。" -f $when, $latest.Remain }
        elseif ($change) { $summary = "{0} 还剩 {1}，本把{2}。" -f $when, $latest.Remain, $change }
    }

    $rows = ""
    $previousRemain = $null
    if ($points.Count -eq 1) { $previousRemain = Get-PreviousNumber }
    for ($i = 0; $i -lt $points.Count; $i++) {
        $point = $points[$i]
        $change = Get-ChangeText $previousRemain $point.Remain
        if ($point.Remain -match '^\d+$') { $previousRemain = $point.Remain }
        $weight = if ($i -eq $points.Count - 1) { "700" } else { "400" }
        $changeColor = if ($change -like "少*") { "#9a3412" } else { "#666" }
        $clock = Encode-Html (Get-Clock $point.Time)
        $remain = Encode-Html $point.Remain
        $changeHtml = Encode-Html $change
        $rows += "<tr><td style=`"padding:9px 28px 9px 0;border-bottom:1px solid #eee;font-weight:$weight`">$clock</td><td style=`"padding:9px 0;border-bottom:1px solid #eee;text-align:right;font-family:Consolas,'Sarasa Mono',monospace;font-size:18px;font-weight:$weight`">$remain</td><td style=`"padding:9px 0 9px 28px;border-bottom:1px solid #eee;text-align:right;color:$changeColor;font-weight:$weight`">$changeHtml</td></tr>"
    }

    $headline = Encode-Html $latest.Remain
    $summaryHtml = Encode-Html $summary
    return @"
<div style="font-family:'Microsoft YaHei','Segoe UI',sans-serif;font-size:16px;line-height:1.6;color:#222;background:#ffffff;padding:4px 2px">
  <div style="font-size:14px;color:#666">本周还可获得飞沙令</div>
  <div style="font-size:40px;line-height:1.2;font-weight:700;font-family:Consolas,'Sarasa Mono',monospace;margin:2px 0 8px">$headline</div>
  <div style="margin:0 0 16px">$summaryHtml</div>
  <table style="border-collapse:collapse;font-size:16px;color:#222">
    <tr>
      <th style="text-align:left;padding:0 28px 8px 0;color:#666;font-weight:600;border-bottom:2px solid #ddd">时间</th>
      <th style="text-align:right;padding:0 0 8px;color:#666;font-weight:600;border-bottom:2px solid #ddd">剩余</th>
      <th style="text-align:right;padding:0 0 8px 28px;color:#666;font-weight:600;border-bottom:2px solid #ddd">变化</th>
    </tr>
    $rows
  </table>
</div>
"@
}

function Get-PreviousNumber {
    $path = Join-Path (Split-Path $PSScriptRoot -Parent) "debug/royale-weekly-left.txt"
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $lines = [System.IO.File]::ReadAllLines($path, [System.Text.UTF8Encoding]::new($false))
    $skippedNewest = $false
    for ($i = $lines.Length - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match '(\d{1,5})\s*$') {
            if (-not $skippedNewest) {
                $skippedNewest = $true
                continue
            }
            return $Matches[1]
        }
    }
    return $null
}

try {
    $configPath = Find-MailConfig
    if (-not $configPath) {
        Write-Output "mail skipped: no config"
        return
    }
    $cfg = Get-Content -LiteralPath $configPath -Raw -Encoding utf8 | ConvertFrom-Json
    $to = [string]$cfg.to
    $from = [string]$cfg.from
    $user = [string]$cfg.user
    $password = [string]$cfg.password
    $hostName = [string]$cfg.host
    $port = 587
    if ($cfg.port) { $port = [int]$cfg.port }
    if ([string]::IsNullOrWhiteSpace($from)) { $from = $user }
    if ([string]::IsNullOrWhiteSpace($to) -or [string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($password) -or [string]::IsNullOrWhiteSpace($hostName)) {
        Write-Output "mail skipped: no auth"
        return
    }

    $points = @(Get-RemainPoints $Line)
    $remain = "未知"
    if ($points.Count -gt 0) { $remain = $points[$points.Count - 1].Remain }
    elseif (-not [string]::IsNullOrWhiteSpace($Line)) {
        $parts = $Line.Trim() -split "\s+"
        $remain = $parts[$parts.Length - 1]
    }
    $subject = "BJX 飞沙令剩余 $remain"
    $msg = New-Object System.Net.Mail.MailMessage
    $msg.From = $from
    [void]$msg.To.Add($to)
    $msg.SubjectEncoding = [System.Text.Encoding]::UTF8
    $msg.BodyEncoding = [System.Text.Encoding]::UTF8
    $msg.IsBodyHtml = $true
    $msg.Subject = $subject
    $msg.Body = Get-MailBody $Line

    $smtp = New-Object System.Net.Mail.SmtpClient($hostName, $port)
    $smtp.EnableSsl = $true
    $smtp.Timeout = 5000
    $smtp.UseDefaultCredentials = $false
    $smtp.Credentials = New-Object System.Net.NetworkCredential($user, $password)
    $smtp.Send($msg)
    $msg.Dispose()
    $smtp.Dispose()
    Add-MailLog "mail sent remain=$remain points=$($points.Count)"
    Write-Output "mail sent"
}
catch {
    $safe = $_.Exception.Message
    if ($password) { $safe = $safe.Replace($password, "***") }
    Add-MailLog ("mail failed: " + $safe)
    Write-Output ("mail failed: " + $safe)
}

return

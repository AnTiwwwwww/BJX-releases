# 给任务脚本追加一行纯文本日志。文件在 debug\bjx.log，导出日志时会一起复制。
function Write-BjxLog([string] $Message) {
    try {
        $dir = Join-Path (Split-Path $PSScriptRoot -Parent) "debug"
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir | Out-Null
        }
        $path = Join-Path $dir "bjx.log"
        $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
        [System.IO.File]::AppendAllText($path, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    }
    catch {
    }
}

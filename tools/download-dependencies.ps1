[CmdletBinding()]
param([string] $OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'deps' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'docs/dependencies.json') -Raw | ConvertFrom-Json
foreach ($asset in $manifest.assets) {
    if ([IO.Path]::GetFileName($asset.file) -ne $asset.file -or $asset.url -notlike 'https://*') { throw '依赖地址或文件名不合法。' }
    $target = Join-Path $OutputDirectory $asset.file
    if (-not (Test-Path -LiteralPath $target)) {
        Invoke-WebRequest -Uri $asset.url -OutFile $target -TimeoutSec 180
    }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $asset.sha256) {
        throw "依赖校验失败：$($asset.file)。未使用该文件，请检查下载来源。"
    }
    Write-Output ('PASS: ' + $asset.file)
}

# 检查真实 EXE 元数据与提示文本，不弹窗、不打开网页、不修改系统安装。
[CmdletBinding()]
param([string] $AssemblyPath = '')
$ErrorActionPreference = 'Stop'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$sandbox = Join-Path $tempRoot ('BJX PowerShell 检查 ' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
function Assert-True([bool] $Value, [string] $Message) { if (-not $Value) { throw "FAIL: $Message" } }
try {
    if (-not $AssemblyPath) {
        & (Join-Path $PSScriptRoot 'build.ps1') -OutputDirectory (Join-Path $sandbox 'tools') | Out-Null
        $AssemblyPath = Join-Path $sandbox 'tools/bjx-run.exe'
    }
    $assembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $AssemblyPath).Path))
    $runtime = $assembly.GetType('PowerShellRuntime', $true)
    $flags = [Reflection.BindingFlags]'Static,NonPublic'
    $find = $runtime.GetMethod('Find7', $flags)
    function Find-TestPowerShell([string] $SearchPath, [string] $InstallDirectory) {
        return $find.Invoke($null, @($SearchPath, $InstallDirectory))
    }
    $guide = $runtime.GetMethod('InstallationGuide', $flags)
    $pwshFile = (Get-Command pwsh.exe -CommandType Application | Select-Object -First 1).Source
    $pwshDirectory = Split-Path $pwshFile -Parent
    $missing = Join-Path $sandbox '不存在'
    Assert-True ($null -eq (Find-TestPowerShell $missing $missing)) '缺少 PowerShell 7 时应阻止继续'
    Assert-True ((Find-TestPowerShell $pwshDirectory $missing) -eq $pwshFile) 'PATH 中存在 PowerShell 7 时不提示升级'
    $fallback = Join-Path $sandbox 'Program Files/PowerShell/7'
    New-Item -ItemType Directory -Path $fallback -Force | Out-Null
    Copy-Item -LiteralPath $pwshFile -Destination (Join-Path $fallback 'pwsh.exe')
    Assert-True ((Find-TestPowerShell $missing (Join-Path $sandbox 'Program Files')) -eq (Join-Path $fallback 'pwsh.exe')) 'PATH 未刷新时可使用标准安装位置'
    $legacy = Join-Path $sandbox '只有系统 5.1'
    New-Item -ItemType Directory -Path $legacy | Out-Null
    Copy-Item -LiteralPath (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') -Destination (Join-Path $legacy 'pwsh.exe')
    Assert-True ($null -eq (Find-TestPowerShell $legacy $missing)) '不能把 Windows PowerShell 的文件版本 10 误当成 PowerShell 7'
    Assert-True ((Find-TestPowerShell ($legacy + ';' + '"' + $pwshDirectory + '"') $missing) -eq $pwshFile) '跳过旧版后应继续找到 PowerShell 7'
    $legacyGuide = $guide.Invoke($null, @($true))
    Assert-True ($legacyGuide.Contains('检测到 Windows PowerShell 5.1') -and $legacyGuide.Contains('winget install') -and $legacyGuide.Contains('learn.microsoft.com') -and $legacyGuide.Contains('并存')) '5.1 提示应包括安装命令、官网及并存说明'
    Assert-True (-not $guide.Invoke($null, @($false)).Contains('检测到 Windows PowerShell 5.1')) '未确认 5.1 时不能误报检测结果'
    Write-Output 'PASS: PowerShell 缺失、PATH、标准安装位置、旧版误识别、并存、安装指引共 7 项；未打开实际弹窗。'
} finally {
    $resolved = [IO.Path]::GetFullPath($sandbox)
    if (-not $resolved.StartsWith($tempRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolved -Leaf) -notlike 'BJX PowerShell 检查 *') { throw '临时检查目录边界失败，未清理。' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

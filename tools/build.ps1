# 构建自有 C# 辅助程序。默认只写 build/tools，不替换正在运行的程序。
[CmdletBinding()]
param([string] $OutputDirectory = '')

$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or -not [Environment]::Is64BitOperatingSystem) {
    throw 'BJX 辅助程序需要 Windows x64 和 PowerShell 7。'
}
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'build/tools' }
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw '.NET Framework 4.x C# 编译器不存在；请先安装或启用 .NET Framework 4.8。'
}
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
foreach ($name in @('bjx-run', 'bjx-royale-clock')) {
    $source = Join-Path $PSScriptRoot ($name + '.cs')
    $target = Join-Path $outputPath ($name + '.exe')
    $compilerArgs = @('/nologo', '/target:winexe', '/platform:x64', '/optimize+', '/codepage:65001', ('/out:' + $target), $source, (Join-Path $PSScriptRoot 'bjx-powershell.cs'))
    & $compiler @compilerArgs
    $compilerExit = $LASTEXITCODE
    if ($compilerExit -ne 0) { throw "$name 编译失败（退出码 $compilerExit）；若目标正在运行，请先关闭 BJX 或换用输出目录。" }
    Write-Output ([pscustomobject]@{ Program = $name; Path = $target; SHA256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash })
}

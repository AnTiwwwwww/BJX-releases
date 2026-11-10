# Build the pinned MXU source with BJX's small GitHub updater patch.
[CmdletBinding()]
param([string] $SourceDirectory = '', [string] $OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$recipe = Get-Content -LiteralPath (Join-Path $projectRoot 'integrations/mxu/build.json') -Raw | ConvertFrom-Json
$patch = Join-Path $projectRoot 'integrations/mxu/github-update.patch'
if ((Get-FileHash -LiteralPath $patch -Algorithm SHA256).Hash -ne $recipe.patch_sha256) { throw 'MXU patch hash mismatch.' }
if (-not $SourceDirectory) { $SourceDirectory = Join-Path $projectRoot 'build/mxu-runtime' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'build/mxu-patched' }
$source = [IO.Path]::GetFullPath($SourceDirectory)
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $source) {
    # Actions may restore only Cargo's ignored target directory before checkout.
    $children = @(Get-ChildItem -LiteralPath $source -Force)
    if ($children.Count -ne 1 -or $children[0].Name -ne 'src-tauri' -or -not $children[0].PSIsContainer) {
        throw 'MXU source destination already exists; use a fresh directory.'
    }
    $cargoChildren = @(Get-ChildItem -LiteralPath $children[0].FullName -Force)
    if ($cargoChildren.Count -ne 1 -or $cargoChildren[0].Name -ne 'target' -or -not $cargoChildren[0].PSIsContainer) {
        throw 'MXU source destination contains more than the restored Cargo cache.'
    }
}
function Invoke-Checked([string] $Executable, [string[]] $Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed ($LASTEXITCODE)." }
}
New-Item -ItemType Directory -Path $source -Force | Out-Null
Invoke-Checked git @('-C', $source, 'init', '--quiet')
Invoke-Checked git @('-C', $source, 'config', 'core.autocrlf', 'false')
Invoke-Checked git @('-C', $source, 'remote', 'add', 'origin', $recipe.upstream)
Invoke-Checked git @('-C', $source, 'fetch', '--depth=1', 'origin', $recipe.revision)
Invoke-Checked git @('-C', $source, 'checkout', '--detach', 'FETCH_HEAD')
Invoke-Checked git @('-C', $source, 'apply', '--check', $patch)
Invoke-Checked git @('-C', $source, 'apply', $patch)
New-Item -ItemType Directory -Path $output -Force | Out-Null
Push-Location -LiteralPath $source
try {
    Invoke-Checked pnpm @('install', '--frozen-lockfile')
    Invoke-Checked pnpm @('test')
    Invoke-Checked pnpm @('build')
    # Real Rust tests cover SHA-256 corruption, the install gate, and full-update file preservation.
    Invoke-Checked cargo @('test', '--locked', '--release', '--target', 'x86_64-pc-windows-msvc', '--manifest-path', 'src-tauri/Cargo.toml', '--lib', 'bjx_update', '--', '--test-threads=1')
    Invoke-Checked pnpm @('tauri', 'build', '--no-bundle', '--target', 'x86_64-pc-windows-msvc')
    & (Join-Path $PSScriptRoot 'test-update-gate.ps1') -SourcePath (Join-Path $source 'src/App.tsx')
    Invoke-Checked git @('add', '--all')
    Invoke-Checked git @('-c', 'user.name=BJX build', '-c', 'user.email=build@example.invalid', '-c', 'core.hooksPath=NUL', 'commit', '--quiet', '-m', 'Build MXU with BJX GitHub updater')
    $sourceZip = Join-Path $output ('MXU-source-v' + $recipe.runtime_version + '.zip')
    Invoke-Checked git @('archive', '--format=zip', ('--output=' + $sourceZip), 'HEAD')
    $sourceHash = (Get-FileHash -LiteralPath $sourceZip -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath ($sourceZip + '.sha256') -Value ($sourceHash + '  ' + [IO.Path]::GetFileName($sourceZip)) -Encoding ascii
    Copy-Item -LiteralPath 'src-tauri/target/x86_64-pc-windows-msvc/release/mxu.exe' -Destination (Join-Path $output 'mxu.exe')
    $runtimeHash = (Get-FileHash -LiteralPath (Join-Path $output 'mxu.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
    [ordered]@{
        runtime_version=$recipe.runtime_version; upstream=$recipe.upstream; revision=$recipe.revision
        patch_sha256=$recipe.patch_sha256; exe_sha256=$runtimeHash; source_sha256=$sourceHash
        checks=@('frontend tests', 'TypeScript and Vite build', 'Rust BJX update tests', '6 real App install-gate cases')
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'build-receipt.json') -Encoding utf8
} finally { Pop-Location }
Write-Output "PASS: built MXU $($recipe.runtime_version) in $output"

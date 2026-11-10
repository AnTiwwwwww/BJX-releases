# 验证可发布整包，所有运行和升级模拟均在独立临时目录内完成。
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $PackagePath,
    [string] $ReportPath = ''
)
$ErrorActionPreference = 'Stop'
$package = (Get-Item -LiteralPath $PackagePath).FullName
if (-not $ReportPath) { $ReportPath = Join-Path (Split-Path $package -Parent) 'release-validation.json' }
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$sandbox = Join-Path $tempRoot ('BJX 整包测试 [隔离] ' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
function Assert-True([bool] $Value, [string] $Message) { if (-not $Value) { throw "FAIL: $Message" } }
function Assert-Contained([string] $Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    if (-not $absolute.StartsWith($sandbox.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw '测试目录边界检查失败。'
    }
    return $absolute
}
try {
    $extracted = Assert-Contained (Join-Path $sandbox '新版 解压')
    $zip = [IO.Compression.ZipFile]::OpenRead($package)
    try {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            Assert-True ($name -notmatch '(^/|(^|/)\.\.(/|$)|:)' -and $names.Add($name)) 'ZIP 路径必须唯一且不能逃出解压目录'
            Assert-True ($name -notmatch '(?i)(^|/)(\.git|config|debug|cache|export|deps|source-snapshot)(/|$)|(^|/)accounts\.csv($|\.)|\.local\.|^tests/fixtures/royale/.+\.png$') '整包不得包含本机资料'
        }
    } finally { $zip.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($package, $extracted)
    $manifest = Get-Content -LiteralPath (Join-Path $extracted 'BETA_MANIFEST.json') -Raw | ConvertFrom-Json
    $actualFiles = @(Get-ChildItem -LiteralPath $extracted -Recurse -File -Force)
    Assert-True ($actualFiles.Count -eq $manifest.files.Count + 1) '整包清单应覆盖所有文件'
    $manifestNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $manifest.files) {
        Assert-True ($manifestNames.Add($entry.path)) '清单不能重复文件'
        $path = [IO.Path]::GetFullPath((Join-Path $extracted $entry.path))
        Assert-True ($path.StartsWith($extracted + '\', [StringComparison]::OrdinalIgnoreCase)) '清单路径必须位于解压目录内'
        $file = Get-Item -LiteralPath $path
        Assert-True ($file.Length -eq $entry.bytes -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $entry.sha256) '整包文件大小与哈希应匹配'
    }
    foreach ($required in @('mxu.exe', 'maafw/MaaFramework.dll', 'tools/bjx-run.exe', 'tools/bjx-royale-clock.exe',
        'resource/model/ocr/det.onnx', 'resource/model/ocr/rec.onnx', 'resource/model/ocr/keys.txt',
        'licenses/MXU-AGPL-3.0.txt', 'third-party/UPSTREAM_SOURCES.md', 'accounts.example.csv')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $extracted $required) -PathType Leaf) "缺少运行或许可文件：$required"
    }
    $interface = Get-Content -LiteralPath (Join-Path $extracted 'interface.json') -Raw | ConvertFrom-Json
    Assert-True ($interface.version -eq $manifest.version) '界面与清单版本必须一致'
    $hash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
    $sidecar = (Get-Content -LiteralPath ($package + '.sha256') -Raw).Trim()
    Assert-True ($sidecar -eq ($hash + '  ' + [IO.Path]::GetFileName($package))) 'ZIP 校验文件必须匹配'

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = Join-Path $extracted 'mxu.exe'
    $psi.WorkingDirectory = $extracted
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.ArgumentList.Add('--help')
    $process = [Diagnostics.Process]::Start($psi)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(20000)) { $process.Kill($true); throw '隔离 MXU --help 超时。' }
        Assert-True ($process.ExitCode -eq 0 -and $stdout.GetAwaiter().GetResult() -match 'Usage|用法') '整包 MXU 应能启动帮助命令'
    } finally { $process.Dispose() }
    & pwsh -NoLogo -NoProfile -NonInteractive -File (Join-Path $extracted 'tools/test-royale-deadline.ps1') -AssemblyPath (Join-Path $extracted 'tools/bjx-royale-clock.exe')
    Assert-True ($LASTEXITCODE -eq 0) '整包计时器应通过日期边界检查'
    & pwsh -NoLogo -NoProfile -NonInteractive -File (Join-Path $extracted 'tools/test-powershell-runtime.ps1') -AssemblyPath (Join-Path $extracted 'tools/bjx-run.exe')
    Assert-True ($LASTEXITCODE -eq 0) '整包应能正确识别 PowerShell 环境并提供安装指引'

    # MXU 2.8.0 apply_full_update：只替换新包拥有的顶层条目。
    # 用虚构资料验证这一文件操作规则；不冒充实际 GUI 安装验收。
    $installed = Assert-Contained (Join-Path $sandbox '旧版 用户目录')
    $backup = Assert-Contained (Join-Path $sandbox '模拟备份')
    New-Item -ItemType Directory -Path $installed, $backup | Out-Null
    $fixtures = @{
        'config/mxu-BJX.json' = '{"test_setting":"keep"}'
        'config/wecom.local.json' = '{"enabled":false}'
        'config/mail.local.json' = '{"enabled":false}'
        'accounts.csv' = "账号,密码,区服,角色名称,备注`n测试账号,,测试区服,测试角色,仅测试"
    }
    $before = @{}
    foreach ($relative in $fixtures.Keys) {
        $target = Assert-Contained (Join-Path $installed $relative)
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Set-Content -LiteralPath $target -Value $fixtures[$relative] -Encoding utf8BOM
        $before[$relative] = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    }
    $obsolete = Assert-Contained (Join-Path $installed 'resource/pipeline/obsolete.json')
    New-Item -ItemType Directory -Path (Split-Path $obsolete -Parent) -Force | Out-Null
    Set-Content -LiteralPath $obsolete -Value '{}' -Encoding utf8
    foreach ($item in (Get-ChildItem -LiteralPath $extracted -Force)) {
        $destination = Assert-Contained (Join-Path $installed $item.Name)
        if (Test-Path -LiteralPath $destination) {
            $backupPath = Assert-Contained (Join-Path $backup $item.Name)
            Move-Item -LiteralPath $destination -Destination $backupPath
        }
        Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force
    }
    foreach ($relative in $fixtures.Keys) {
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $installed $relative) -Algorithm SHA256).Hash -eq $before[$relative]) '升级模拟必须逐字节保留账号和配置'
    }
    Assert-True (-not (Test-Path -LiteralPath $obsolete)) '升级模拟必须清除旧任务目录中的过期文件'
    Assert-True ((Get-Content -LiteralPath (Join-Path $installed 'interface.json') -Raw | ConvertFrom-Json).version -eq $manifest.version) '升级模拟必须安装新版本'
    & python -X utf8 (Join-Path $extracted 'tools/test-release-runtime.py')
    Assert-True ($LASTEXITCODE -eq 0) '整包流水线与 OCR 应能加载，辅助 Agent 应能连接'
    [ordered]@{
        schema_version=1; package=[IO.Path]::GetFileName($package); version=$manifest.version
        sha256=$hash; payload_files=$manifest.files.Count; checked_at_utc=[DateTime]::UtcNow.ToString('o')
        integrity='passed'; private_files_excluded='passed'; mxu_help='passed'; deadline_cases=10; powershell_environment_cases=7
        config_and_accounts_preserved='passed: isolated simulation of MXU 2.8.0 full-update file rule'
        obsolete_resource_removed='passed'; pipeline_and_agent='passed'; gui_update='not run'; game_input='not performed'
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ReportPath -Encoding utf8
    Write-Output 'PASS: 整包完整性、隐私排除、隔离 MXU 启动、10 个截止用例；升级模拟保留 4 份虚构配置并删除旧任务文件。'
} finally {
    $resolved = [IO.Path]::GetFullPath($sandbox)
    if (-not $resolved.StartsWith($tempRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolved -Leaf) -notlike 'BJX 整包测试 *') { throw '临时测试目录边界检查失败，未清理。' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

# 检查公开包内容，并从解压后的无 Git 目录构建；仅使用临时目录和虚构测试数据。
$ErrorActionPreference = 'Stop'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$sandbox = Join-Path $tempRoot ('BJX 源码包测试 ' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
function Assert-True([bool] $Value, [string] $Message) { if (-not $Value) { throw "FAIL: $Message" } }
try {
    $package = & (Join-Path $PSScriptRoot 'export-source.ps1') -OutputFile (Join-Path $sandbox 'source.zip')
    $extracted = Join-Path $sandbox '解压目录 with spaces'
    [IO.Compression.ZipFile]::ExtractToDirectory($package.Path, $extracted)
    $manifest = Get-Content -LiteralPath (Join-Path $extracted 'PUBLICATION_MANIFEST.json') -Raw | ConvertFrom-Json
    foreach ($entry in $manifest.files) {
        Assert-True ($entry.path -notmatch '^accounts\.csv|^config/|^debug/|^export/|^maafw/|^deps/|(^|/)\.git/|\.exe$|^tests/fixtures/royale/.+\.png$|\.(delivery|finalize|finalize-summary|browser-check|visual-check)\.json$') '包内不得存在本机资料或原始回执'
        $path = Join-Path $extracted $entry.path
        Assert-True ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $entry.sha256) '清单与文件校验值必须一致'
    }
    $bundles = @(Get-ChildItem -LiteralPath (Join-Path $extracted '.archify') -Filter 'source-snapshot.bundle' -Recurse -File)
    Assert-True ($bundles.Count -eq 1) '公开包只包含当前路线图的源码快照'
    foreach ($bundle in $bundles) {
        $summary = Get-Content -LiteralPath (Join-Path $bundle.DirectoryName 'validation.json') -Raw | ConvertFrom-Json
        Assert-True ((Get-FileHash -LiteralPath $bundle.FullName -Algorithm SHA256).Hash -eq $summary.source_snapshot_sha256) '源码快照与公开验证摘要必须一致'
    }
    Push-Location -LiteralPath $sandbox
    try {
        & (Join-Path $extracted 'tools/build.ps1') | Out-Null
        & pwsh -NoLogo -NoProfile -NonInteractive -File (Join-Path $extracted 'tools/test-royale-deadline.ps1') -AssemblyPath (Join-Path $extracted 'build/tools/bjx-royale-clock.exe')
        Assert-True ($LASTEXITCODE -eq 0) '源码包构建出的计时器应通过日期用例'
        & pwsh -NoLogo -NoProfile -NonInteractive -File (Join-Path $extracted 'tools/test-portability.ps1')
        Assert-True ($LASTEXITCODE -eq 0) '源码包应能独立完成路径和构建测试'
    } finally { Pop-Location }

    $fakeToken = 'gh' + 'p_' + ('A' * 40)
    @{ token=$fakeToken } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $extracted 'examples/leak.example.json') -Encoding utf8
    $rejected = $false
    try {
        & (Join-Path $extracted 'tools/export-source.ps1') -OutputFile (Join-Path $sandbox 'must-not-exist.zip') | Out-Null
    } catch {
        Assert-True (-not $_.Exception.Message.Contains($fakeToken)) '拒绝信息不能泄漏命中内容'
        $rejected = $_.Exception.Message -like '*公开资料扫描发现*'
    }
    Assert-True $rejected '导出必须拒绝意外写入模板的令牌'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $sandbox 'must-not-exist.zip'))) '拒绝后不得留下可发布 ZIP'
    Write-Output 'PASS: 公开包文件范围与哈希、源码快照、无 Git 解压目录构建、异地运行、令牌阻断且不输出原文'
} finally {
    $resolved = [IO.Path]::GetFullPath($sandbox)
    if (-not $resolved.StartsWith($tempRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolved -Leaf) -notlike 'BJX 源码包测试 *') { throw '临时测试目录边界检查失败，未清理' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

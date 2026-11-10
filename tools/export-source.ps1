# 导出可公开的源码快照；使用允许清单，保留本机资料与原始 Git 历史。
param([string] $OutputFile = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$readme = Get-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Raw
$diagramLink = [regex]::Match($readme, '\]\((\.archify/[^/)]+)/bjx-royale-route\.html\)')
if (-not $diagramLink.Success) { throw 'README 中没有当前路线图入口，不能确定公开的图版本。' }
$publicDiagram = $diagramLink.Groups[1].Value
if (-not $OutputFile) { $OutputFile = Join-Path $projectRoot ('export/BJX-source-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip') }
$outputPath = [IO.Path]::GetFullPath($OutputFile)
if (Test-Path -LiteralPath $outputPath) { throw '输出文件已存在，请换用新文件名。' }
$outputParent = Split-Path $outputPath -Parent
New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
$stage = Join-Path $outputParent ('.source-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $stage | Out-Null

function Test-PublicPath([string] $Relative) {
    if ($Relative.StartsWith('.archify/') -and -not $Relative.StartsWith($publicDiagram + '/')) { return $false }
    if ($Relative -match '(?i)(^|/)(\.git|source-snapshot)(/|$)' -or
        $Relative -match '(?i)\.local\.' -or
        $Relative -match '\.(delivery|finalize|finalize-summary|browser-check|visual-check)\.json$') { return $false }
    if ($Relative -in @('.gitignore', '.gitattributes', 'AGENTS.md', 'GLOSSARY.md', 'LICENSE', 'README.md', 'THIRD_PARTY_NOTICES.md', 'interface.json', 'accounts.example.csv')) { return $true }
    if ($Relative -match '^\.github/workflows/[^/]+\.yml$') { return $true }
    if ($Relative -match '^docs/.+\.(md|json)$|^licenses/[^/]+\.txt$|^examples/[^/]+\.json$|^tools/[^/]+\.(ps1|py|cs)$') { return $true }
    if ($Relative -match '^resource/pipeline/[^/]+\.json$|^resource/(image|model)/\.gitkeep$') { return $true }
    if ($Relative -match '^scripts/(README\.md|imported\.json|_template/.+\.json)$|^tests/fixtures/royale/README\.md$') { return $true }
    if ($Relative -match '^\.archify/[^/]+/(README\.md|\.gitignore|candidate\.json|validation\.json|source-snapshot\.bundle|bjx-royale-route\.html|(?:visual-check|review-2)/[^/]+\.(png|html)|visual-check/manual-review\.json)$') { return $true }
    return $false
}

$secretPatterns = @(
    'https://qyapi\.weixin\.qq\.com/cgi-bin/webhook/send\?key=[A-Za-z0-9-]{12,}',
    '(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})',
    '-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----',
    '(?:AKIA|ASIA)[A-Z0-9]{16}',
    '(?i)[a-z]:[\\/]+Users[\\/]+(?!Public(?:[\\/]|$))[^\\/\s"'']+',
    '(?im)(?:password|passwd|smtp_password|app_password|api[_-]?key|secret|token)["'']?\s*[:=]\s*["'']([^"''\r\n]{10,})'
)
try {
    $files = @()
    $files += Get-ChildItem -LiteralPath $projectRoot -File -Force
    foreach ($folder in @('docs', 'licenses', 'examples', 'tools', 'resource', 'scripts', 'tests/fixtures/royale', '.archify', '.github')) {
        $path = Join-Path $projectRoot $folder
        if (Test-Path -LiteralPath $path) { $files += Get-ChildItem -LiteralPath $path -Recurse -File -Force }
    }
    $manifest = @()
    foreach ($file in $files) {
        $relative = [IO.Path]::GetRelativePath($projectRoot, $file.FullName).Replace('\', '/')
        if (-not (Test-PublicPath $relative)) { continue }
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "源码包不收录符号链接：$relative" }
        if ($file.Extension -notin @('.png', '.bundle')) {
            $text = [IO.File]::ReadAllText($file.FullName)
            foreach ($pattern in $secretPatterns) {
                if ([regex]::IsMatch($text, $pattern)) { throw "公开资料扫描发现需检查的内容：$relative（未输出原文）" }
            }
        }
        $target = Join-Path $stage $relative
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
        $manifest += [ordered]@{ path=$relative; bytes=$file.Length; sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    foreach ($required in (@('README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'interface.json', 'tools/build.ps1', 'docs/installation.md') + @(($publicDiagram + '/candidate.json'), ($publicDiagram + '/bjx-royale-route.html'), ($publicDiagram + '/validation.json')))) {
        if (-not (Test-Path -LiteralPath (Join-Path $stage $required))) { throw "源码包缺少必需文件：$required" }
    }
    [ordered]@{
        schema_version=1
        kind='BJX-public-source-snapshot'
        created_at_utc=[DateTime]::UtcNow.ToString('o')
        excludes=@('accounts', 'local configuration', 'logs and game captures', 'compiled executables and runtimes', 'working repository Git history', 'raw local tool receipts')
        files=$manifest
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $stage 'PUBLICATION_MANIFEST.json') -Encoding utf8
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $outputPath)
    $hash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath ($outputPath + '.sha256') -Value ($hash + '  ' + [IO.Path]::GetFileName($outputPath)) -Encoding ascii
    Write-Output ([pscustomobject]@{ Path=$outputPath; SHA256=$hash; Files=$manifest.Count })
} finally {
    $resolved = [IO.Path]::GetFullPath($stage)
    $expectedParent = [IO.Path]::GetFullPath($outputParent).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($expectedParent, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolved -Leaf) -notlike '.source-*') { throw '临时导出目录边界检查失败，未清理' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

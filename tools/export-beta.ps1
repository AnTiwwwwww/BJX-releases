# 为朋友内测生成整包；从允许清单源码和校验通过的上游依赖组装，不复制本机运行目录。
[CmdletBinding()]
param(
    [string] $OutputFile = '',
    [string] $DependencyDirectory = ''
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or -not [Environment]::Is64BitOperatingSystem) {
    throw '请使用 Windows x64 和 PowerShell 7 打包。'
}
$projectRoot = Split-Path $PSScriptRoot -Parent
$interface = Get-Content -LiteralPath (Join-Path $projectRoot 'interface.json') -Raw | ConvertFrom-Json
$dependencies = Get-Content -LiteralPath (Join-Path $projectRoot 'docs/dependencies.json') -Raw | ConvertFrom-Json
if (-not $DependencyDirectory) { $DependencyDirectory = Join-Path $projectRoot 'deps' }
$dependencyRoot = [IO.Path]::GetFullPath($DependencyDirectory)

$assets = @{}
foreach ($asset in $dependencies.assets) {
    if ([IO.Path]::GetFileName($asset.file) -ne $asset.file) { throw '依赖清单只能使用文件名。' }
    $path = Join-Path $dependencyRoot $asset.file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "缺少依赖 $($asset.file)，请按 docs/installation.md 下载。" }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $asset.sha256) {
        throw "依赖校验失败：$($asset.file)，未生成内测包。"
    }
    $assets[$asset.name] = $path
}
foreach ($required in @('MaaFramework', 'MXU', 'OCR-det', 'OCR-rec', 'OCR-keys')) {
    if (-not $assets.ContainsKey($required)) { throw "依赖清单缺少 $required。" }
}

if (-not $OutputFile) {
    $OutputFile = Join-Path $projectRoot ('export/BJX-win-x86_64-v' + $interface.version + '.zip')
}
$outputPath = [IO.Path]::GetFullPath($OutputFile)
if ((Test-Path -LiteralPath $outputPath) -or (Test-Path -LiteralPath ($outputPath + '.sha256'))) {
    throw '输出文件或校验文件已存在，请换用新文件名。'
}
$outputParent = Split-Path $outputPath -Parent
New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
$stage = Join-Path $outputParent ('.beta-' + [guid]::NewGuid().ToString('n'))
$packageRoot = Join-Path $stage 'BJX'
New-Item -ItemType Directory -Path $stage | Out-Null

try {
    $sourceZip = Join-Path $stage 'BJX-source.zip'
    & (Join-Path $PSScriptRoot 'export-source.ps1') -OutputFile $sourceZip | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($sourceZip, $packageRoot)
    # 新清单将覆盖源码、编译产物和依赖，不保留只描述源码的旧清单。
    Remove-Item -LiteralPath (Join-Path $packageRoot 'PUBLICATION_MANIFEST.json')

    $maaExtract = Join-Path $stage 'maa-upstream'
    $mxuExtract = Join-Path $stage 'mxu-upstream'
    [IO.Compression.ZipFile]::ExtractToDirectory($assets.MaaFramework, $maaExtract)
    [IO.Compression.ZipFile]::ExtractToDirectory($assets.MXU, $mxuExtract)
    Copy-Item -LiteralPath (Join-Path $maaExtract 'bin') -Destination (Join-Path $packageRoot 'maafw') -Recurse
    Copy-Item -LiteralPath (Join-Path $mxuExtract 'mxu.exe') -Destination (Join-Path $packageRoot 'mxu.exe')
    $ocrDirectory = Join-Path $packageRoot 'resource/model/ocr'
    New-Item -ItemType Directory -Path $ocrDirectory -Force | Out-Null
    foreach ($name in @('OCR-det', 'OCR-rec', 'OCR-keys')) {
        Copy-Item -LiteralPath $assets[$name] -Destination $ocrDirectory
    }

    foreach ($upstream in @(
        @{ Name='MaaFramework'; Root=$maaExtract },
        @{ Name='MXU'; Root=$mxuExtract }
    )) {
        $noticeRoot = Join-Path $packageRoot ('third-party/' + $upstream.Name)
        foreach ($file in (Get-ChildItem -LiteralPath $upstream.Root -Recurse -File)) {
            if ($file.Name -notmatch '^(LICENSE|NOTICE|COPYING|COPYRIGHT)(\..*)?$' -and
                -not ($file.DirectoryName -eq $upstream.Root -and $file.Name -like 'README*')) { continue }
            $relative = [IO.Path]::GetRelativePath($upstream.Root, $file.FullName)
            $target = Join-Path $noticeRoot $relative
            New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target
        }
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/upstream-sources.md') -Destination (Join-Path $packageRoot 'third-party/UPSTREAM_SOURCES.md')
    & (Join-Path $packageRoot 'tools/build.ps1') -OutputDirectory (Join-Path $packageRoot 'tools') | Out-Null

    $startHere = @'
BJX {VERSION} 内测

完整解压后，先阅读 docs/beta-testing.md，再打开 mxu.exe。
需要 Windows x64、PowerShell 7（加入 PATH）及 Microsoft Edge WebView2 Runtime。

只测试「单人吃鸡刷币」和按需使用的「定时开始」。其余任务均未完成。
吃鸡运行前请手动切换至旗舰心法；窗口客户区 1920×1080，界面缩放 100%。
吃鸡截止时间默认为任务启动日期的次日凌晨 01:30。

第三方许可见 THIRD_PARTY_NOTICES.md、licenses/ 和 third-party/。
此包不含打包者的账号、通知配置、日志或游戏截图。
'@
    $startHere = $startHere.Replace('{VERSION}', $interface.version)
    Set-Content -LiteralPath (Join-Path $packageRoot '内测先读.txt') -Value $startHere -Encoding utf8BOM

    $files = @()
    foreach ($file in (Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Force | Sort-Object FullName)) {
        $relative = [IO.Path]::GetRelativePath($packageRoot, $file.FullName).Replace('\', '/')
        if ($relative -match '(?i)(^|/)(\.git|config|debug|cache|export|deps|source-snapshot)(/|$)|(^|/)accounts\.csv($|\.)|\.local\.' -or
            $relative -match '^tests/fixtures/royale/.+\.png$') {
            throw "内测包出现本机资料路径：$relative"
        }
        $files += [ordered]@{ path=$relative; bytes=$file.Length; sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    [ordered]@{
        schema_version=1
        kind='BJX-beta-windows-x64'
        version=$interface.version
        created_at_utc=[DateTime]::UtcNow.ToString('o')
        beta_tasks=@('单人吃鸡刷币', '定时开始')
        prerequisites=@('Windows x64', 'PowerShell 7 on PATH', 'Microsoft Edge WebView2 Runtime')
        dependency_assets=$dependencies.assets
        files=$files
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $packageRoot 'BETA_MANIFEST.json') -Encoding utf8

    [IO.Compression.ZipFile]::CreateFromDirectory($packageRoot, $outputPath)
    $hash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath ($outputPath + '.sha256') -Value ($hash + '  ' + [IO.Path]::GetFileName($outputPath)) -Encoding ascii
    [pscustomobject]@{ Path=$outputPath; SHA256=$hash; Files=$files.Count; Bytes=(Get-Item -LiteralPath $outputPath).Length }
} finally {
    $resolved = [IO.Path]::GetFullPath($stage)
    $expectedParent = [IO.Path]::GetFullPath($outputParent).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($expectedParent, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolved -Leaf) -notlike '.beta-*') { throw '临时打包目录边界检查失败，未清理。' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

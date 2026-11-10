# 从原始 Archify 回执生成可公开摘要；不修改原始回执或图文件。
param([Parameter(Mandatory)] [string] $DiagramDirectory)
$ErrorActionPreference = 'Stop'
$directory = (Resolve-Path -LiteralPath $DiagramDirectory).Path
$candidatePath = Join-Path $directory 'candidate.json'
$candidate = Get-Content -LiteralPath $candidatePath -Raw | ConvertFrom-Json
$valid = @()
foreach ($file in (Get-ChildItem -LiteralPath $directory -Filter '*.finalize-summary.json' -Recurse -File)) {
    $receipt = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if ($receipt.ok -and $receipt.status -eq 'pass') { $valid += [pscustomobject]@{ File=$file; Receipt=$receipt } }
}
if (-not $valid) { throw '没有通过的 Archify 回执，不能导出验证摘要。' }
$receipt = ($valid | Sort-Object { $_.File.LastWriteTimeUtc } -Descending | Select-Object -First 1).Receipt
$artPath = Join-Path $directory ([IO.Path]::GetFileName($receipt.artifact.path))
foreach ($entry in @(@($candidatePath, $receipt.specification.sha256), @($artPath, $receipt.artifact.sha256))) {
    if ((Get-FileHash -LiteralPath $entry[0] -Algorithm SHA256).Hash -ne $entry[1]) { throw '图源或 HTML 与通过的回执不一致。' }
}
$browser = Get-Content -LiteralPath $receipt.evidence.browserCheckReceipt -Raw | ConvertFrom-Json
if ($browser.status -ne 'pass' -or $browser.artifact.sha256 -ne $receipt.artifact.sha256) { throw '浏览器证据与图不一致。' }
$manual = Get-ChildItem -LiteralPath $directory -Filter 'manual-review.json' -Recurse -File | Select-Object -First 1
$review = 'not-recorded'
if ($manual) {
    $record = Get-Content -LiteralPath $manual.FullName -Raw | ConvertFrom-Json
    if ($record.artifact_sha256 -eq $receipt.artifact.sha256 -and $record.status -eq 'pass') { $review = 'pass' }
}
$output = [ordered]@{
    schema_version = 1
    kind = 'redacted-validation-summary'
    description = '从原始回执提取的公开摘要，省略本机路径及命令行；不替代原始 Archify 回执。'
    diagram_type = $receipt.type
    tool_version = $receipt.update.installedVersion
    source_revision = $candidate.meta.repository.revision
    specification = @{ file='candidate.json'; sha256=$receipt.specification.sha256; bytes=$receipt.specification.bytes }
    artifact = @{ file=[IO.Path]::GetFileName($artPath); sha256=$receipt.artifact.sha256; bytes=$receipt.artifact.bytes }
    gates = $receipt.gates
    diagnostics = $receipt.diagnostics
    browser_evidence = 'pass'
    visual_review = $review
    source_snapshot_sha256 = (Get-FileHash -LiteralPath (Join-Path $directory 'source-snapshot.bundle') -Algorithm SHA256).Hash.ToLowerInvariant()
}
$output | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $directory 'validation.json') -Encoding utf8
Write-Output 'PASS: 图源、HTML 和浏览器证据一致，已导出无本机路径的公开摘要。'

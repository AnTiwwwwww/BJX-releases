# 把 scripts/<名字>/pack.json 收成 scripts/imported.json，并把流水线复制进资源目录。
# 以 _ 开头的目录会被跳过。
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$scripts = Join-Path $root "scripts"
$utf8 = New-Object System.Text.UTF8Encoding $false

$tasks = @()
$options = [ordered]@{}
$pipelineDest = Join-Path $root "resource\pipeline\scripts"
$imageRoot = Join-Path $root "resource\image\scripts"

if (Test-Path $pipelineDest) {
    Remove-Item $pipelineDest -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $pipelineDest | Out-Null
if (Test-Path $imageRoot) {
    Remove-Item $imageRoot -Recurse -Force
}

Get-ChildItem -Path $scripts -Directory | Where-Object { -not $_.Name.StartsWith("_") } | Sort-Object Name | ForEach-Object {
    $packPath = Join-Path $_.FullName "pack.json"
    if (-not (Test-Path $packPath)) {
        Write-Output ("跳过 {0}：没有 pack.json" -f $_.Name)
        return
    }
    $scriptName = $_.Name
    $pack = Get-Content -LiteralPath $packPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($pack.task) {
        foreach ($task in @($pack.task)) {
            $tasks += $task
        }
    }
    if ($pack.option) {
        foreach ($prop in $pack.option.PSObject.Properties) {
            $options[$prop.Name] = $prop.Value
        }
    }
    $pipeline = Join-Path $_.FullName "pipeline"
    if (Test-Path $pipeline) {
        Get-ChildItem -Path $pipeline -Filter *.json -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($pipeline.Length).TrimStart("\", "/")
            $destName = "{0}-{1}" -f $scriptName, ($rel -replace "[\\/]", "-")
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $pipelineDest $destName)
        }
    }
    $image = Join-Path $_.FullName "image"
    if (Test-Path $image) {
        $imageDest = Join-Path $imageRoot $_.Name
        New-Item -ItemType Directory -Force -Path $imageDest | Out-Null
        Copy-Item -Path (Join-Path $image "*") -Destination $imageDest -Recurse -Force
    }
    Write-Output ("导入 {0}" -f $_.Name)
}

$imported = [ordered]@{
    task   = $tasks
    option = $options
}
$json = $imported | ConvertTo-Json -Depth 30
[System.IO.File]::WriteAllText((Join-Path $scripts "imported.json"), $json + "`n", $utf8)
Write-Output ("任务 {0} 项，写入 scripts/imported.json" -f $tasks.Count)

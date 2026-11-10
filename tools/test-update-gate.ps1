# 执行固定版本 MXU 中真实的自动安装条件；不启动界面或安装更新。
[CmdletBinding()]
param([string] $SourcePath = '')
$ErrorActionPreference = 'Stop'
$recipe = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'integrations/mxu/build.json') -Raw | ConvertFrom-Json
$expectedHash = $recipe.app_sha256
$download = ''
try {
    if (-not $SourcePath) {
        $SourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'build/mxu-runtime/src/App.tsx'
    }
    # Git 在 Windows 检出时可能转换换行；按上游 UTF-8 / LF 内容校验。
    $sourceBytes = [Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText([IO.Path]::GetFullPath($SourcePath)).Replace("`r`n", "`n"))
    $sourceHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($sourceBytes)).ToLowerInvariant()
    if ($sourceHash -ne $expectedHash) {
        throw 'MXU 自动安装检查源文件与固定版本不一致，未执行。'
    }
    $harness = @'
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(process.argv[1], 'utf8');
const match = source.match(/const tryAutoInstallUpdate = useCallback\(\(\) => \{([\s\S]*?)\r?\n  \}, \[\]\);/);
if (!match) throw new Error('Cannot locate the pinned MXU install callback');
const cases = [
  ['completed + stopped', {}, false, true],
  ['one running instance', {instances: [{isRunning:false}, {isRunning:true}]}, false, false],
  ['pending task launch', {}, true, false],
  ['download incomplete', {downloadStatus:'downloading'}, false, false],
  ['install in progress', {installStatus:'installing'}, false, false],
  ['confirmation already pending', {autoInstallPending:true}, false, false],
];
for (const [name, overrides, launchPending, expected] of cases) {
  const calls = [];
  const state = {
    downloadStatus:'completed', installStatus:'idle', autoInstallPending:false,
    instances:[{isRunning:false}], ...overrides,
    setAutoInstallPending:v => calls.push(['pending',v]),
    setShowInstallConfirmModal:v => calls.push(['modal',v]),
  };
  vm.runInNewContext(`(function(){${match[1]} })()`, {
    useAppStore:{getState:()=>state}, autoTaskLaunchPendingRef:{current:launchPending}, log:{info:()=>{}}
  }, {timeout:1000});
  const wanted = expected ? [['pending',true],['modal',true]] : [];
  if (JSON.stringify(calls) !== JSON.stringify(wanted)) throw new Error(`FAIL: ${name}`);
  console.log(`PASS: ${name}`);
}
'@
    & node -e $harness ([IO.Path]::GetFullPath($SourcePath))
    if ($LASTEXITCODE -ne 0) { throw 'MXU 运行中禁止自动安装检查失败。' }
    Write-Output 'PASS: BJX 定制 MXU 真实前端回调的 6 个条件；未进行界面安装。'
} finally {
    if ($download -and (Test-Path -LiteralPath $download)) { Remove-Item -LiteralPath $download }
}

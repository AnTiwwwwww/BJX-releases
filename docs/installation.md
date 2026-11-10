# 安装、构建与本地配置

BJX 是 Windows x64 项目。以下组合用于当前版本验证，升级依赖后需要重新跑回归。源码包不包含第三方程序、模型或游戏截图。

| 组件 | 当前验证版本 | 用途 |
| --- | --- | --- |
| PowerShell | 7（本机 7.6.9） | 执行任务辅助脚本，支持 PATH 或标准安装目录 |
| .NET Framework | 4.x，使用系统 `Framework64/v4.0.30319/csc.exe` | 构建和运行自有 C# 辅助程序 |
| [MXU](https://github.com/MaaXYZ/MXU/releases/tag/v2.8.0) | 2.8.0 Windows x86_64 | 任务界面 |
| [MaaFramework](https://github.com/MaaXYZ/MaaFramework/releases/tag/v5.14.3) | 5.14.3 Windows x86_64 | 识别、控制器与自定义动作 |
| [MaaCommonAssets](https://github.com/MaaXYZ/MaaCommonAssets/tree/dabcd4681ac990dc4361de26416d986abd80e4aa/OCR/ppocr_v4/zh_cn) | `ppocr_v4/zh_cn`，固定版本见依赖清单 | 中文 OCR |

## 1. 准备目录与 PowerShell

将 BJX 放在有写权限的目录，中文和空格路径均可。下文所有命令在 BJX 根目录的 PowerShell 7 终端中执行；运行时日志等资料总是相对项目目录定位，与启动时的工作目录无关。

按 [Microsoft 的安装说明](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows) 安装 PowerShell 7，或使用：

```powershell
winget install --id Microsoft.PowerShell --exact --source winget
```

安装后重新打开终端和 BJX，让 PATH 生效。运行 `Get-Command pwsh.exe` 应能找到实际程序。Windows 自带的 `powershell.exe` 5.1 不能代替它；如果使用 PowerShell ZIP 便携版，请将其目录加入 PATH。PowerShell 7 与系统 5.1 并存，不需要卸载 5.1。

BJX 在启动任务的 Agent 和辅助脚本前检查 PowerShell 7。只有 5.1 时会弹出安装指引，提供上面的安装命令与微软说明页入口，并阻止本次启动；未检测到 5.1 时显示通用缺失提示。已经安装 7 时正常继续，不因系统仍有 5.1 而提醒。PATH 尚未刷新时会尝试 `%ProgramFiles%\PowerShell\7\pwsh.exe`。弹窗只提供指引，不自动下载或安装软件。

## 2. 获取并核对依赖

[dependencies.json](dependencies.json) 固定下载地址和 SHA-256。压缩包的校验值已与上游 Release 元数据核对；OCR 文件已与固定版本的 Git 文件对象及本机使用的模型核对。

以下命令下载到本机 `deps/`，只复用校验通过的文件，不修改正在使用的运行库：

```powershell
$ErrorActionPreference = 'Stop'
$manifest = Get-Content -LiteralPath './docs/dependencies.json' -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path './deps' -Force | Out-Null
foreach ($asset in $manifest.assets) {
    $target = Join-Path './deps' $asset.file
    if (-not (Test-Path -LiteralPath $target)) {
        Invoke-WebRequest -Uri $asset.url -OutFile $target
    }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $asset.sha256) {
        throw "校验失败：$($asset.file)。请移走该下载文件后重新下载。"
    }
}
```

关闭 BJX 后，完成以下文件放置：

1. 解压 MXU 压缩包，将其中的 `mxu.exe` 放到 BJX 根目录。保留上游许可文件，不覆盖 BJX 自己的 `LICENSE`。
2. 解压 MaaFramework 压缩包，将其中 **`bin` 的全部内容** 放到 BJX 的 `maafw/`。不只复制单个 DLL，也不混用不同版本。
3. 创建 `resource/model/ocr/`，将 `deps/det.onnx`、`deps/rec.onnx`、`deps/keys.txt` 复制进去，三个文件必须来自同一套中文 OCR v4 模型。

目录应为：

```text
BJX/
├── mxu.exe
├── interface.json
├── maafw/
│   ├── MaaFramework.dll
│   ├── MaaAgentClient.dll
│   ├── MaaAgentServer.dll
│   └── ...其余 bin 文件
├── tools/
│   ├── bjx-run.exe
│   └── bjx-royale-clock.exe
└── resource/model/ocr/
    ├── det.onnx
    ├── rec.onnx
    └── keys.txt
```

## 3. 从源码构建辅助程序

构建脚本使用 Windows 的 .NET Framework 编译器，不需要 NuGet 包。找不到编译器时先安装或启用 .NET Framework 4.8。

```powershell
pwsh -NoLogo -NoProfile -File ./tools/build.ps1
```

产物位于 `build/tools/`，默认不会覆盖当前运行的程序。关闭 BJX 后安装：

```powershell
Copy-Item -LiteralPath './build/tools/bjx-run.exe' -Destination './tools/bjx-run.exe'
Copy-Item -LiteralPath './build/tools/bjx-royale-clock.exe' -Destination './tools/bjx-royale-clock.exe'
```

也可用 `-OutputDirectory <目录>` 指定输出位置。源码包默认只带 `.cs` 源码，首次使用必须构建并复制这两个 EXE。Git 工作区内已有的辅助 EXE 也可按此步骤重新构建。

## 4. 可选本地资料

- 账号表：复制根目录的 `accounts.example.csv` 为 `accounts.csv`，一行一个角色。已有文件请保留；当前只用于维护资料，自动登录尚未接入。
- 企业微信：将 `examples/wecom-webhook.example.json` 复制为 `config/wecom-webhook.local.json`，填写自己的机器人地址。
- 邮件：将 `examples/royale-mail.example.json` 复制为 `config/royale-mail.local.json`，填写 SMTP 主机、端口、账号、授权码、发件人和收件人。当前脚本使用 STARTTLS；请按服务商说明填写，默认端口 587。

`config/` 不存在时先创建。通知配置缺失或字段为空会跳过发送，正常任务可继续。账号表和本地配置为明文，请只在本机填写；它们被 Git 忽略，也不会进入公开源码包。

## 5. 运行与验证

启动根目录 `mxu.exe`，选择已登录的无界窗口，保持客户区 1920×1080、界面缩放 100%。运行吃鸡前手动切换至旗舰心法。当前内测只勾选吃鸡和按需使用的定时开始，其余任务标注「未完成」。朋友使用整包时可跳过下载运行库和编译步骤，见 [内测说明](beta-testing.md)。完整操作和停止快捷键见根目录 README。

无需启动游戏的构建和路径检查：

```powershell
pwsh -NoLogo -NoProfile -File ./tools/test-portability.ps1
pwsh -NoLogo -NoProfile -File ./tools/test-royale-deadline.ps1
pwsh -NoLogo -NoProfile -File ./tools/test-royale-deadline.ps1 -AssemblyPath ./build/tools/bjx-royale-clock.exe
```

OCR 回放另外需要 Python、Pillow 和本机截图样本，见 [回归说明](../tests/fixtures/royale/README.md)。公开源码包不会携带游戏截图；缺少样本时不能把未执行的回放当作通过。

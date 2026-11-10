# 公开源码的资料范围

## 使用干净源码包

在项目根目录执行：

```powershell
pwsh -NoLogo -NoProfile -File ./tools/export-source.ps1
```

结果位于 `export/BJX-source-<时间>.zip`，旁边有 SHA-256 文件。解压后根目录的 `PUBLICATION_MANIFEST.json` 列出每个文件的长度和 SHA-256；可以用于检查包内容。

用 `pwsh -NoLogo -NoProfile -File ./tools/test-source-package.ps1` 检查包的排除范围和文件哈希，并验证解压到其他目录后仍能从源码构建、运行路径测试，以及令牌检查能阻断误发布。

导出使用明确的路径和扩展名允许清单，并检查常见令牌、私钥、硬编码密码及 Windows 用户目录。命中时只报告文件名，不输出疑似密钥。此检查不等于完整安全审计；维护允许清单时需同时核对新增文件的来源和用途。

源码包排除账号表、通知配置、日志、游戏截图、外部运行库、OCR 模型、自有编译产物、原始工具回执和工作仓库 `.git` 历史。路线图只收录 README 指向的当前版本。游戏截图留在本机用于回归，素材范围见 [第三方声明](../THIRD_PARTY_NOTICES.md)。两个辅助 EXE 由包内源码构建，步骤见 [安装说明](installation.md)。

## 旧私有历史

当前工作树的清理不会删除旧提交里的内容。旧私有提交曾包含游戏回归截图和带本机路径的工具回执；将原仓库直接改为 Public，仍会公开这些历史内容。

公开仓库为 [BJX-releases](https://github.com/AnTiwwwwww/BJX-releases)，从允许清单导出的源码建立独立历史；原私有仓库保留作为开发档案。不得推送原私有仓库的历史到公开仓库，也不修改原仓库可见性。路线图附带的 `source-snapshot.bundle` 是只包含对应公开源码的独立验证快照，不包含工作仓库的完整历史。

## 版本发布

`.github/workflows/release.yml` 仅在上述公开仓库执行。推送 `v<版本>` 标签后，Windows CI 下载并校验固定依赖、从干净源码构建、检查安装包、验证配置保留和任务停止条件，生成程序 ZIP、源码 ZIP 及各自 SHA-256。上传成功后发布 GitHub Release，beta/rc 标为预发布，不标为 Latest。也可手动运行工作流，默认只生成构建产物；勾选 publish 才发布。

每次发布先修改 `interface.json` 的 `version` 与 `title`，添加 `docs/releases/v<版本>.md`。修改任务时先按 `AGENTS.md` 同步路线图，再导出干净源码。在公开仓库的独立检出目录中审核并提交这一份导出内容，确认无账号、配置、日志和游戏截图后推送 main 与对应标签。标签必须与界面版本一致；已有 Release 不会被覆盖。

本地可先执行以下验证。程序包默认输出到 `export/BJX-win-x86_64-v<版本>.zip`，已存在的包不会覆盖。

```powershell
pwsh -NoLogo -NoProfile -File ./tools/download-dependencies.ps1
pwsh -NoLogo -NoProfile -File ./tools/test-source-package.ps1
pwsh -NoLogo -NoProfile -File ./tools/test-update-gate.ps1
$package = ./tools/export-beta.ps1
./tools/test-release-package.ps1 -PackagePath $package.Path
```

`test-release-package.ps1` 在隔离目录检查逐文件哈希、私有资料排除、MXU 启动与截止计时，再模拟 MXU 2.8.0 的顶层替换规则，确认虚构账号和配置逐字节保留、旧任务文件清除。`test-update-gate.ps1` 校验固定版 MXU 源文件哈希并执行其中真实的自动安装条件，覆盖任务运行、等待启动、下载未完成等状态。它们不操作正在运行的 BJX，也不代替软件内下载、安装和重启验收。

目前未接入 Mirror酱，`interface.json` 未配置 RID，0.x 版本也不启用 MXU 常规更新检查。当前用户通过 Releases 手动更新；后续接入需要独立完成服务注册、版本策略和端到端验收。

## 联网升级接入计划

优先复用 MXU 的内置更新器。现有公开仓库、Windows 整包、SHA-256 和标签发布工作流已经具备；下一步为 Mirror酱 项目接入和真实旧版本升级验收。接入前继续标为手动更新，不填虚构 RID，也不把离线模拟记作联网验收通过。

1. 由项目负责人联系 [Mirror酱 项目接入](https://github.com/MirrorChyan/docs#开始接入)，提供 `AnTiwwwwww/BJX-releases` 仓库及 `v0.4.1-beta.1` 的程序 ZIP。当前只分发 Windows x64 的 MXU 整包，计划先使用 beta 通道。官方会确认 RID、平台划分、上传与日志同步方案，并提供接入 PR 或交付说明。
2. 收到官方信息后，在公开仓库的 `Settings → Secrets and variables → Actions` 设置 `MirrorChyanUploadToken`。这是 CI 上传凭证，用户下载使用的 CDK 是另一种凭证；Token 无需发送到聊天或写入源码。配置路径见 [官方 FAQ](https://github.com/MirrorChyan/docs/blob/main/FAQ.md#如何设置仓库的-mirrorchyanuploadtoken)。
3. 审核接入 PR，将确认后的 RID 与平台设置接到 `interface.json`，使包版本、Git 标签、服务端版本和 beta 通道一致。现有 CI 只验证和发布 GitHub Release，需依据接入方案增加上传及更新日志同步；不要假定 `GITHUB_TOKEN` 创建 Release 会自动触发另一条 `release` 工作流，应实际验证触发链路。
4. 处理当前 MXU 2.8.0 的版本限制：其 [`isDebugVersion`](https://github.com/MaaXYZ/MXU/blob/v2.8.0/src/services/updateService.ts#L403) 会过滤低于 `1.0.0` 的版本，`1.0.0-beta.1` 也在过滤范围。可使用高于该门槛的 beta 版本（例如 `1.0.1-beta.1`，仍明确标注内测），或保留 0.x 并维护支持该版本规则的 MXU 构建。应在接入时确定并验证方案，不能单靠添加 RID 启用当前包的更新。
5. 发出首次接入包。现有 `0.4.1-beta.1` 未包含 RID，用户需要手动换包一次；接入包验收后，后续版本才通过软件联网检查、下载和安装。
6. 在隔离的旧版目录验证整个过程：能发现目标 beta 版本，选中正确 Windows x64 包，下载和校验通过；任务运行或定时等待时不安装重启；停止后可以完成安装并重启；`config/` 与 `accounts.csv` 保留；再次检查不重复提示同一版本；断网或下载失败时现有任务仍可使用。先验证完整包，增量包另行验收。

用户不填 CDK 也能查版本；MXU 2.8.0 在版本接口成功且无 CDK 时可从 GitHub 下载。Mirror酱 加速下载需要有效 CDK。该版本仍依赖 Mirror酱 查询版本，不能把 GitHub 下载路径理解为服务不可用时必定能自动查到新版本。[官方说明](https://github.com/MirrorChyan/docs/blob/main/FAQ.md#不填-cdk也能检查更新吗)，[MXU 下载源选择](https://github.com/MaaXYZ/MXU/blob/v2.8.0/src/services/updateService.ts#L872)。

首次沟通可使用下面的项目信息，不含任何凭证：

> 项目 BJX，公开仓库 https://github.com/AnTiwwwwww/BJX-releases 。使用 MXU 2.8.0，已有 Windows x64 ZIP 整包和 GitHub Actions 标签发布流程。申请接入版本检查及更新包分发，先使用 beta 通道，保留无 CDK 时从 GitHub 下载。当前 Release 为 v0.4.1-beta.1，要分发的文件为 BJX-win-x86_64-v0.4.1-beta.1.zip，源码 ZIP 不作为客户端更新包。希望确认 RID、平台和版本命名，并提供上传、更新日志同步及请求示例。

## 路线图公开验证记录

每个路线图目录的 `validation.json` 是从通过的 Archify 回执提取的公开摘要，包含图源和 HTML 校验值、源码快照版本、结构检查、浏览器检查及已记录的预览检查状态。它省略本机路径和命令行，不冒充原始工具回执。

原始 `*.delivery.json`、`*.finalize*.json`、`*.browser-check.json` 和 `*.visual-check.json` 留在本机并被 Git 忽略；它们仍可用于本机的严格校验。图源或 HTML 改动后，需要先重新生成并验证，再更新公开摘要：

```powershell
pwsh -NoLogo -NoProfile -File ./tools/export-diagram-evidence.ps1 -DiagramDirectory '<路线图目录>'
```

不得仅修改摘要中的通过标记或哈希。涉及任务代码和配置时，按根目录 `AGENTS.md` 同步图源、HTML、预览和证据。

## 用户日志

游戏内报错截图可能含角色名、聊天和账号信息。日志导出功能只在本机整理日志与报错样本，不自动上传，也不会复制 `accounts.csv` 和 `config/`。需要向他人提供故障资料时，应检查导出内容后再发送。

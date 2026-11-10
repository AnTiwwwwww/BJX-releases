# BJX 的 MXU 更新器补丁

本目录固定上游 MXU 2.8.0 的提交，并保存 BJX 的 GitHub Releases 更新补丁。`build.json` 记录上游、补丁校验值和定制运行时版本；`github-update.patch` 包含对应源码与测试。

补丁提供公开 GitHub 更新检查、0.x 内测版本比较、精确 Windows x64 整包匹配、下载和安装前 SHA-256 校验，以及安装与任务启动互斥。无 RID 时不显示 CDK 输入，默认内测频道；稳定频道只接收正式发布。用户数据不随整包覆盖。

在 Windows x64 安装 Node.js 22、pnpm 10.28.0、Rust stable 和 Visual Studio C++ 构建工具后，在 BJX 根目录运行 `./tools/build-mxu.ps1`。构建使用上游锁文件；失败不会生成可供整包使用的构建回执。发布工作流负责执行前端、Rust、运行门禁和整包检查。

MXU 及本补丁按 AGPL-3.0 分发，许可见 `licenses/MXU-AGPL-3.0.txt`。每次 Release 附带 `MXU-source-v2.8.0-bjx.1.zip` 及 SHA-256，包含完整对应源码、锁文件和测试；BJX 源码包提供本补丁与构建脚本。BJX 自有资源的 MIT 许可不改变第三方代码许可。

这里的补丁是 BJX 自行维护的改动，不代表 MXU 上游已经接受这些修改。升级上游版本时必须重新审查并执行测试。

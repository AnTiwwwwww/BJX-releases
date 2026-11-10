# 第三方组件与素材许可

BJX 自有代码和文档适用根目录的 [MIT 许可证](LICENSE)。第三方程序、模型、字体和游戏素材遵循各自许可；下表记录当前使用的来源与范围。

| 项目 | 版本或来源 | 许可与本地副本 | 在 BJX 中的用途 |
| --- | --- | --- | --- |
| [MaaFramework](https://github.com/MaaXYZ/MaaFramework/tree/v5.14.3) | 5.14.3 | [LGPL-3.0](licenses/MaaFramework-LGPL-3.0.txt)，及其引用的 [GPL-3.0](licenses/GPL-3.0.txt) | 用户另行下载运行库；BJX 的 C# Agent 通过公开动态库接口调用 |
| [MXU](https://github.com/MaaXYZ/MXU/tree/v2.8.0) | 2.8.0-bjx.1 | [AGPL-3.0](licenses/MXU-AGPL-3.0.txt) | 基于固定上游源码的任务界面，含 [BJX 更新补丁与构建方法](integrations/mxu/README.md)；Release 同时提供完整对应源码 |
| [MaaCommonAssets](https://github.com/MaaXYZ/MaaCommonAssets/tree/dabcd4681ac990dc4361de26416d986abd80e4aa) | `ppocr_v4/zh_cn`，固定版本见 `docs/dependencies.json` | 资源仓库 [MIT](licenses/MaaCommonAssets-MIT.txt) | OCR 模型整理与转换来源；模型由用户另行下载 |
| [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR/tree/release/2.7) | PP-OCRv4；来源由 MaaCommonAssets 的模型 README 说明 | 上游项目 [Apache-2.0](licenses/PaddleOCR-Apache-2.0.txt) | OCR 模型的原始上游；模型及附带资料应保留相应上游声明 |
| [Archify](https://github.com/tt-a1i/archify) | 3.0.1 | [MIT](licenses/Archify-MIT.txt)，包含 tt-a1i 和 Cocoon AI 的版权声明 | 路线图的 HTML 模板和查看器代码 |
| [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) | 路线图内嵌 Google Fonts v24 子集，字节校验值在 HTML 内 | [SIL OFL-1.1](licenses/JetBrainsMono-OFL-1.1.txt) | 路线图内嵌字体；HTML 同时保留完整字体许可 |

PowerShell、.NET Framework、Python、Pillow 等开发或执行工具由用户自行安装，不随包分发。上表的「用户另行下载」指源码包安装方式；朋友内测整包另行收录固定版本的 MXU、MaaFramework 和 OCR 模型，并保留发布包的原始许可、README 以及 [对应源码地址](docs/upstream-sources.md)。MaaFramework 和 MXU 还使用其他上游组件，本表不替代其完整随附声明；正式公开发行整合包前仍需核对传递依赖的许可及源码提供要求。

## 游戏画面与商标

剑网3无界的游戏画面、UI、美术、文字标识和商标属于相应权利人，BJX 不对这些内容授予 MIT 许可，也不代表获得游戏官方认可。

`tests/fixtures/royale/*.png` 是本机调试时裁剪的游戏界面样本。目前未核实独立再分发授权，公开源码包默认排除这些图片；本机样本继续用于回归。源码包保留样本名称、裁剪位置和采集方法，使用者可以自行采集。原始日志、截图、账号表和配置同样不进入源码包。

路线图的流程内容由 BJX 代码整理而来；其 HTML 查看器和内嵌字体分别适用上表所列许可。导出或转载图表时请保留相关许可文件。

## 发布范围

`tools/export-source.ps1` 生成的包包括 BJX 源码、配置模板、文档、路线图和许可文件，不包括第三方运行库、OCR 模型、自有编译产物、游戏截图或 Git 历史。安装及构建方式见 [安装说明](docs/installation.md)，首次公开资料整理见 [发布说明](docs/publishing.md)。

`tools/export-beta.ps1` 生成朋友内测整包，在上述干净源码基础上加入校验通过的固定版本运行库、OCR 模型和当次构建的自有辅助程序。使用步骤和实机验收范围见 [内测说明](docs/beta-testing.md)。本机账号、通知配置、日志、游戏截图和个人 Git 历史仍不收录。

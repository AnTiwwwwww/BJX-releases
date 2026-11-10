# 内测包上游来源

内测包使用下列未经修改的上游发布二进制。文件下载地址和 SHA-256 见包内 `docs/dependencies.json`，上游原始许可和 README 保留在 `third-party/MaaFramework/`、`third-party/MXU/`；BJX 自有源码直接随包提供在 `tools/`、`resource/` 等目录。

| 组件 | 二进制与对应源码 |
| --- | --- |
| MaaFramework 5.14.3 | [发布页](https://github.com/MaaXYZ/MaaFramework/releases/tag/v5.14.3)；[固定源码版本 8963191](https://github.com/MaaXYZ/MaaFramework/tree/8963191215ca49d6b037802acd07d20a4213160a)；[源码 ZIP](https://github.com/MaaXYZ/MaaFramework/archive/8963191215ca49d6b037802acd07d20a4213160a.zip) |
| MXU 2.8.0 | [发布页](https://github.com/MaaXYZ/MXU/releases/tag/v2.8.0)；[固定源码版本 5e923e8](https://github.com/MaaXYZ/MXU/tree/5e923e83b30a102fb78da35c30ee2e1559aea682)；[源码 ZIP](https://github.com/MaaXYZ/MXU/archive/5e923e83b30a102fb78da35c30ee2e1559aea682.zip) |
| MaaCommonAssets 中文 OCR v4 | [固定资源版本](https://github.com/MaaXYZ/MaaCommonAssets/tree/dabcd4681ac990dc4361de26416d986abd80e4aa/OCR/ppocr_v4/zh_cn)；原始上游为 [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR/tree/release/2.7) |

源码 ZIP 不包含 Git 子模块；自行构建 MaaFramework 时按该固定版本的文档递归拉取子模块与构建依赖。上游构建说明：[MaaFramework](https://github.com/MaaXYZ/MaaFramework/tree/8963191215ca49d6b037802acd07d20a4213160a/docs)，[MXU](https://github.com/MaaXYZ/MXU/blob/5e923e83b30a102fb78da35c30ee2e1559aea682/README.md)。

`maafw/` 中的 DirectML、OpenCV、ONNX Runtime 等第三方依赖各自适用其许可，并非全部属于 BJX 的 MIT 或 MaaFramework 的 LGPL。保留随包声明与上游源码地址；正式公开发行整合包前仍需单独核对传递依赖的完整许可及源码提供要求。

# 单人吃鸡任务路线图

本版同步 0.4.1-beta.1：任务启动前检查 PowerShell 7；只有 5.1 或缺少 7 时弹出安装指引并停止本次启动。已装 7 正常继续，支持标准安装目录。主界面与退出后回城都保留原有顶部文字区域，并新增去除按钮图标的文字区域，兼容小地图被新手引导遮挡及浅色背景。每组都要求花萼楼与行记同时命中。先切换至旗舰心法并关闭遮挡引导；未看到退出页不能重排，额度归零和次日 01:30 截止条件保持不变。

包含 [交互图](bjx-royale-route.html)、[图源](candidate.json)、[预览图](visual-check/bjx-royale-route.visual-check.2048x1320.light.png)、[公开验证摘要](validation.json) 和 [预览检查记录](visual-check/manual-review.json)。原始工具回执留在本机并被 Git 忽略。

`source-snapshot.bundle` 保存图中引用的公开源码及独立验证版本。恢复方式：

```powershell
git -c core.autocrlf=false clone ./source-snapshot.bundle source-snapshot
git -C source-snapshot remote set-url origin https://github.com/AnTiwwwwww/BJX.git
```

更新任务代码时同步图源、HTML、预览和证据；重新通过 Archify 检查后，用 `tools/export-diagram-evidence.ps1` 生成不含本机路径的公开摘要。

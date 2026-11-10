# 单人吃鸡与 GitHub 更新路线图

本版对应 0.4.2-beta.1。上方新增可选的 GitHub 检查、下载校验、等待任务停止、安装与重启流程；下方保留开始吃鸡后的主流程。更新入口不属于游戏内点击，不会在一局中触发重新匹配。

安装前再次校验 SHA-256 并检查全部任务状态；安装期间底层阻止启动新任务。账号表和配置受保护。无新版、网络或校验失败不安装；文件安装出错时显示错误和可用的恢复方式，不承诺完整回滚。

吃鸡仍需旗舰心法。未看到退出页不能重排；确认零额度即停止；截止是任务启动日期的次日 01:30。新号主城备用识别只通过故障画面回放，实机修复待确认；手动关闭引导后的恢复不能当作新增识别验收。

包含 [交互图](bjx-royale-route.html)、[图源](candidate.json)、[预览图](visual-check/bjx-royale-route.visual-check.2048x1320.light.png)、[验证摘要](validation.json) 和 [预览检查](visual-check/manual-review.json)。结构、来源和浏览器检查通过，已查看明暗两张预览；原始工具回执留在本机。

`source-snapshot.bundle` 是独立的公开源码验证快照。其中 `build/mxu-bjx/` 路径保存本次定制 MXU 的被引用源码，和上游源码加 BJX 补丁后的字节一致；这些 MXU 文件适用 AGPL-3.0。完整对应源码由 Release 单独提供。

```powershell
git -c core.autocrlf=false clone ./source-snapshot.bundle source-snapshot
git -C source-snapshot remote set-url origin https://github.com/AnTiwwwwww/BJX.git
```

后续任务代码、更新行为和配置变化时，继续同步图源、HTML、预览及验证记录。

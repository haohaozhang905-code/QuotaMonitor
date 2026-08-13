# 安装 QuotaMonitor

1. 从 [GitHub Releases](https://github.com/haohaozhang905-code/QuotaMonitor/releases) 下载最新版本的 `QuotaMonitor-x.y.z.dmg`。
2. 打开 DMG，将 `QuotaMonitor.app` 拖入“应用程序”。
3. 启动 QuotaMonitor，并确保当前 macOS 用户已经登录 Codex。

QuotaMonitor 会运行在 macOS 菜单栏中。它会根据当前本地路由显示 Codex 官方额度或 DeepSeek 余额，并在有可用数据时显示 Token 用量。

通过 cc-switch 将 Claude 接入 DeepSeek，只代表当前 DeepSeek 路由、余额和部分本地请求记录链路可以观察。这不等于 Claude 官方额度显示机制已经完成验证，也不等于 Claude Desktop 的本地用量只能依赖 cc-switch。应用会根据当前系统中实际存在、且能够读取的结构化记录进行统计。

## 设置

- **开机启动：** 打开主面板，在设置中启用“开机启动”。
- **显示语言：** 在主面板中切换简体中文和 English。
- **刷新：** 应用大约每 60 秒检查一次额度和本地 Token 来源。最近活跃的本地会话可能触发更快的 Token 刷新。

首次读取本地数据时，macOS 可能会请求访问相关文件的权限。QuotaMonitor 不会保存、展示或上传 Prompt 和 Response 正文。

## 卸载

1. 在 QuotaMonitor 设置中关闭“开机启动”。
2. 从菜单栏退出 QuotaMonitor。
3. 将“应用程序”中的 QuotaMonitor 移到废纸篓。

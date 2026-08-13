# 隐私说明

QuotaMonitor 是一个本地 macOS 工具，不包含 QuotaMonitor 账号系统、分析 SDK、广告、位置权限或遥测服务。

## 应用会读取哪些本地数据

- 当前版本 Codex 使用的 macOS Keychain 认证信息，或旧版文件认证路径 `CODEX_HOME/auth.json` / `~/.codex/auth.json`。
- `~/.codex/sessions` 中的 Codex Session 日志，用于本地 Token 用量统计。
- `~/.claude/projects` 中的 Claude Code Transcript，只读取模型、用量和时间等结构化字段，用于本地 Token 用量统计。
- 如果系统中存在并且能够读取，当前实现会读取 `~/.cc-switch/cc-switch.db` 中 Claude / Claude Desktop 的结构化请求记录，包括模型、Token 数量和时间。
- `~/.workbuddy/traces` 中的 WorkBuddy Trace。旧版文件直接提供 Token 汇总；新版文件需要流式读取本地 Trace，以定位结构化的 generation usage 字段。

通过 cc-switch 将 Claude 接入 DeepSeek，主要用于观察当前 DeepSeek 路由、余额和部分本地请求记录。这不等于 Claude 官方额度显示机制已经完成验证，也不代表 Claude Desktop 的本地用量只能通过 cc-switch 获得。QuotaMonitor 会根据当前系统中实际存在、且能够读取的结构化记录进行统计。

QuotaMonitor 不会提取、保存、展示或传输对话正文。Claude 的消息文本会被忽略；WorkBuddy 扫描只会保留定位结构化用量字段所需的极小临时字节窗口。

## 网络请求

- Codex 官方额度请求会使用当前本地 Codex Session，直接发送到 OpenAI。
- DeepSeek 余额请求会使用本地路由配置，直接发送到 DeepSeek。

凭据不会发送给 QuotaMonitor 运营的中间服务。Claude 官方额度目前缺少真实会员账号验证，原因是项目作者没有 Claude 会员；这属于验证范围限制，不代表 Claude 官方额度接口不存在。

当前实现从 cc-switch 请求记录读取桌面端可用量时，如果 cc-switch 没有运行，数据可能缺失或保持为旧快照，应用会显示“未采集 / Not captured”，不会自行估算。Claude 单独通过 DeepSeek 路由时，QuotaMonitor 只会读取活动提供方凭据，用于请求 DeepSeek 官方余额接口。

## 存储与日志

QuotaMonitor 不会将原始认证 Token 保存到偏好设置或日志中。应用只保存语言偏好，以及包含数据源路径、修改信息、日期、模型名称和聚合 Token 数量的本地缓存。这些缓存位于用户的 macOS Caches 目录，不包含 Prompt 或 Response 正文。运行日志只记录刷新状态，不记录凭据。

涉及凭据、Token、Keychain 或本地文件访问的安全问题，请按照 [SECURITY.md](SECURITY.md) 的说明私下报告。

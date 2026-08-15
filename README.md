<p align="center">
  <img src="Sources/QuotaMonitor/Resources/AppIcon.png" width="128" alt="QuotaMonitor 图标">
</p>

<h1 align="center">QuotaMonitor</h1>

<p align="center">
  一款原生 macOS 菜单栏 AI 用量监控工具
</p>

<p align="center">
  查看 Codex 额度、DeepSeek 余额，以及多个本地 AI 工具的 Token 用量
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111827?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-FA7343?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/License-MIT-22c55e" alt="MIT License">
</p>

## 项目简介

QuotaMonitor 运行在 macOS 菜单栏中，把 AI 服务的额度状态和本地使用记录集中到一个面板里。

它主要解决两个问题：

- 随时查看 Codex 官方额度、重置时间和可用的 Reset Credits。
- 汇总 Codex、Claude、WorkBuddy 以及其他本地 AI 工具产生的 Token 用量，观察近期消耗趋势。

QuotaMonitor 优先读取本机已有的认证信息、日志、Trace 和 SQLite 数据，并在本地完成解析、缓存和统计。获取官方额度或 DeepSeek 余额时，应用会直接请求对应服务，没有 QuotaMonitor 自己的账号系统或遥测后端。

## 核心功能

### 额度监控

- 在菜单栏和主面板查看 Codex Session、Weekly 剩余额度。
- 显示下一次额度重置时间。
- 显示 Codex Reset Credits 及其过期时间。
- 自动识别 Codex 当前使用官方服务还是 DeepSeek 路由。
- 独立识别 Claude Code 和 Claude Desktop 的路由状态。
- 当使用 DeepSeek 时，显示共享余额以及根据近 7 日消耗估算的可用天数。

### Token 看板

- 支持今日、近 7 日、近 30 日、近 90 日和累计视图。
- 按平台查看 Token 趋势和用量排行。
- 按实际模型名称查看 Token 趋势和用量排行。
- 查看今日总量、日均用量、峰值日期和主要平台/模型。
- 单独查看 DeepSeek 用量，并保留它在平台统计中的归属。
- 对模型名称进行规范化，空模型名、`auto` 和 `unknown` 会归入 `unknown`。

### 本地优先与增量刷新

- 首次启动后恢复本地历史缓存，再在后台刷新新增或发生变化的文件。
- 对本地数据源使用修改时间和文件大小缓存，减少重复解析。
- 文件暂时不可读或格式异常时，尽量保留上一份有效聚合结果。
- 应用保持单实例运行，避免重复读取和重复渲染菜单栏状态。

## 支持的数据来源

### 额度和余额来源

| 来源 | QuotaMonitor 读取的内容 | 当前状态 |
| --- | --- | --- |
| Codex | 官方额度接口、Session/Weekly 使用情况、Reset Credits | 支持 |
| DeepSeek | 官方余额接口 | 支持 |
| Claude 官方额度 | 由于作者没有 Claude 会员，当前缺少真实会员账号验证 | 待验证 |

Codex 当前版本的认证信息通常保存在 macOS Keychain 中，旧版本的 `auth.json` 也会兼容读取。Claude 官方额度显示机制目前缺少真实会员账号验证，因此 README 不把它描述成“功能不可用”，也不把当前未验证状态推导成 Claude 官方接口不存在。

### Token 用量来源

| 来源 | 本地数据位置或形式 | 说明 |
| --- | --- | --- |
| Codex | `~/.codex/sessions` | 读取结构化 Session 使用记录 |
| Claude Code | `~/.claude/projects` | 读取项目 Transcript 中的 usage 字段 |
| Claude Desktop | 本地结构化请求记录；当前实现接入 `~/.cc-switch/cc-switch.db` | 用于当前可读取的桌面端请求用量和模型记录 |
| WorkBuddy | `~/.workbuddy/traces` | 支持旧版 Trace 汇总和新版结构化 generation usage |
| Qoder | 本地 Session/Event 日志 | 根据稳定请求 ID 去重 |
| 其他工具 | JSON、JSONL 或 SQLite 数据 | 只采集明确的 Token 字段 |

当前额外支持的本地用量来源包括：

`OpenCode`、`Hermes Agent`、`OpenClaw`、`Cursor`、`Antigravity`、`Cline`、`Kimi CLI / Kimi Code / Kimi Desktop`、`Qwen CLI`、`Trae Work`、`千问办公`、`Grok Build`、`GitHub Copilot`、`Pi / Oh My Pi`、`Zed`、`Kilo Code`、`MiMo Code`、`ZCode / GLM`、`Kiro`、`CodeBuddy`、`Proma` 和 `Reasonix`。

只有本地记录中存在明确 Token 字段时，QuotaMonitor 才会纳入统计。普通聊天文本、被粘贴到聊天中的 JSON、长度或上限字段，以及无法确认属于一次模型请求的数字，都不会被当作 Token 用量。

部分工具可以通过环境变量指定自定义数据目录，例如：

```bash
export QUOTAMONITOR_OPENCLAW_HOME="/path/to/openclaw-data"
```

具体工具的默认路径和环境变量名称以 `Sources/QuotaMonitor/Services/AdditionalLocalTokenClient.swift` 为准。

## 统计口径

- Token 总量按照来源支持的结构化字段计算，通常包括输入 Token 和输出 Token。
- Claude 和 WorkBuddy 的缓存 Token 会按照各自记录口径参与输入侧统计。
- Reasoning Token、Cache Hit 和 Cache Write 会作为细节保留，避免重复计入总量。
- 模型名称中包含 `deepseek` 的记录会被识别为 DeepSeek 用量。
- DeepSeek 是跨平台、跨工具的模型子集，不能再次加到平台总量中。
- DeepSeek 可用天数根据余额除以近 7 个自然日的平均估算消耗计算，最多显示 30 天，仅供参考。

## 隐私与安全

QuotaMonitor 是一个本地 macOS 工具：

- 认证信息只用于本机读取和请求对应服务。
- 本地日志、Trace 和数据库只在本机解析。
- 不保存、展示或上传 Prompt 和 Response 正文。
- 不包含 QuotaMonitor 账号系统、广告、分析 SDK、位置权限或遥测服务。
- 获取 Codex 额度时直接请求 OpenAI；获取 DeepSeek 余额时直接请求 DeepSeek。
- 本地缓存只保存文件路径、修改信息、日期、模型名称和聚合后的 Token 数量等必要信息。

详细说明请参阅 [PRIVACY.md](PRIVACY.md)。发现安全问题时，请按照 [SECURITY.md](SECURITY.md) 的方式提交。

## 安装

1. 从 [GitHub Releases](https://github.com/haohaozhang905-code/QuotaMonitor/releases) 下载最新版本的 `QuotaMonitor-x.y.z.dmg`。
2. 打开 DMG，将 `QuotaMonitor.app` 拖入“应用程序”。
3. 启动应用，并确保当前 macOS 用户已经登录 Codex。
4. 如果使用 DeepSeek 路由，请先在 Codex、Claude 或 cc-switch 中完成对应配置。

通过 cc-switch 将 Claude 接入 DeepSeek，只代表当前 DeepSeek 路由、余额和本地请求记录链路可以观察；这不等于 Claude 官方额度显示机制已经验证，也不等于 Claude Desktop 的本地用量只能依赖 cc-switch。QuotaMonitor 会根据当前系统中实际存在、且能够读取的结构化记录进行统计。

QuotaMonitor 会出现在 macOS 菜单栏中。首次读取本地数据时，系统可能会请求访问相关文件的权限。

更完整的安装说明见 [docs/INSTALL.md](docs/INSTALL.md)。

## 使用说明

### 菜单栏

菜单栏入口显示当前额度状态，并在存在数据时显示今日 Token 总量。点击后可以快速查看额度、路由、DeepSeek 余额和最近用量。

### 额度监控

主面板的“额度监控”页用于查看剩余额度、重置时间、Reset Credits 和当前路由状态。

### Token 看板

主面板的“Token 看板”页支持切换时间范围，并在“按平台”和“按模型”之间切换，用于观察总量、趋势和明细。

### 设置

- 简体中文 / English 界面切换。
- 开机启动。
- 手动刷新额度和 Token 数据。
- 查看当前本地数据和隐私说明。

应用默认约每 60 秒刷新一次，最近活跃的本地会话可能触发更快的 Token 刷新。

## 本地开发

### 环境要求

- macOS 14 或更高版本
- Swift 6
- Xcode Command Line Tools
- Apple silicon 或 Intel Mac

项目使用 Swift Package Manager 构建，应用本身采用 SwiftUI 和 AppKit 的原生 macOS 组件。

### 测试与运行

```bash
swift test
./script/build_and_run.sh --verify
```

运行安全检查：

```bash
./script/security_check.sh
```

### 本地打包

不使用发布证书时，可以生成仅用于本地检查的未签名 DMG：

```bash
./script/package_release.sh --unsigned
```

正式发布需要 Developer ID Application 证书和 Apple 公证，流程见 [docs/RELEASING.md](docs/RELEASING.md)。

## 项目结构

```text
Sources/QuotaMonitor/
├── App/          应用入口、菜单栏和主窗口控制
├── Models/       额度、Token 和展示模型
├── Services/     官方接口、本地日志和数据库解析器
├── Stores/       数据刷新、缓存和状态管理
├── Support/      JSONL 读取、格式化、语言和通用工具
├── Views/        菜单栏、下拉面板和主面板界面
└── Resources/    图标与中英文本地化资源

Tests/QuotaMonitorTests/  单元测试和数据源测试
docs/                     安装和发布文档
script/                   构建、运行、安全检查和打包脚本
```

## 当前限制

- Claude 官方额度：作者目前没有 Claude 会员，尚未完成真实会员账号下的剩余额度显示验证。
- 当前通过 cc-switch 使用 DeepSeek 的结果，只能用于说明 DeepSeek 路由、余额和部分本地请求记录的读取情况，不能代替 Claude 官方额度验证。
- Claude Desktop 的本地用量需要根据实际可读取的结构化记录判断；当前实现接入 cc-switch 请求记录，但 README 不将 cc-switch 描述成桌面端本地用量的唯一前置依赖。
- 不同 AI 工具的日志格式可能随上游版本变化，部分来源可能需要额外配置路径。
- 没有明确 Token 字段的记录不会进入统计。
- DeepSeek 剩余天数是基于历史消耗的估算值，不等同于服务商承诺的有效期。

## 贡献

欢迎提交 Issue 和 Pull Request。涉及额度解析、数据源接入或隐私行为的修改，请同时补充说明数据来源和验证方式。

提交改动前建议运行：

```bash
./script/security_check.sh
swift test
./script/build_and_run.sh --verify
```

更多贡献规范见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## License

[MIT](LICENSE) © 2026 QuotaMonitor Contributors

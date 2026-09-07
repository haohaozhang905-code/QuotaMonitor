<p align="center">
  <img src="Sources/QuotaMonitor/Resources/AppIcon.png" width="112" alt="QuotaMonitor 图标">
</p>

<h1 align="center">QuotaMonitor</h1>

<p align="center">在 Mac 菜单栏查看 Codex 剩余额度、DeepSeek 余额和多款 AI 工具的本地 Token 消耗。</p>

<p align="center">
  <a href="docs/INSTALL.md">安装与上手</a> ·
  <a href="docs/DATA_SOURCES.md">工具支持清单</a> ·
  <a href="PRIVACY.md">隐私说明</a> ·
  <a href="https://github.com/haohaozhang905-code/QuotaMonitor/issues">反馈问题</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111827?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-FA7343?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/License-MIT-22c55e" alt="MIT License">
</p>

## 它能帮你做什么

如果你经常在 Codex、Claude Code、WorkBuddy 等 AI 工具之间切换，可以用 QuotaMonitor 回答三个问题：

- **额度还剩多少？** 查看 Codex 5 小时 / 周额度及重置时间；使用已识别的 DeepSeek 路由时查看共享账户余额。
- **最近用了多少？** 按今日、近 7 / 30 / 90 日或累计范围查看本机 Token 总量和趋势。
- **主要用在哪？** 在“按平台”和“按模型”之间切换，查看工具与模型的使用分布。

应用运行在 macOS 菜单栏中，无需额外注册 QuotaMonitor 账号。代码按 MIT 协议开放；你使用的 AI 服务和协助安装的 Agent 可能有各自的费用。

**适用环境：macOS 14+，Apple silicon 或 Intel Mac。** 当前没有 Windows、Linux、iOS 或 Android 客户端；Mac 上的可用数据取决于对应工具实际生成的记录。

## 如何安装

截至 **2026-09-07**，本仓库尚未发布可下载的 Release 安装包，当前可从源码构建。后续安装包以 [GitHub Releases](https://github.com/haohaozhang905-code/QuotaMonitor/releases) 中实际提供的附件为准，源码 ZIP 不等同于可直接安装的应用。

### 交给你的编程 Agent

在具有本机终端和文件操作能力的 Agent 中复制下面这段话，例如你正在使用的 Codex 或 Claude Code：

> 请帮我在这台 Mac 上安装 QuotaMonitor：https://github.com/haohaozhang905-code/QuotaMonitor 。先阅读 README.md 和 docs/INSTALL.md，检查 macOS、Swift 工具链及是否已有安装。若 Releases 有适配的正式安装包，核实来源和签名状态后安装；没有安装包则按仓库指引从源码构建，使用本地 ad-hoc 签名，无需购买开发者证书。安装完成后确认应用能启动、菜单栏入口可见，并告诉我哪些数据源已可用、哪些还需要配置。涉及系统授权或替换已有版本时先说明影响；保留已有源码改动，不要打印或上传凭据、API Key 和完整对话日志，也不要关闭系统安全保护。

普通网页聊天窗口无法直接完成本机安装。Agent 可能需要你批准工具链下载、安装目录写入或系统权限；初次编译也需要等待。

自行操作、更新或卸载，请看 **[完整安装与排查指南](docs/INSTALL.md)**。

## 开始使用

1. **启动 QuotaMonitor。** 在 Mac 顶部菜单栏找到入口，点击查看下拉面板，再进入主面板。
2. **按需要准备数据源。** 查询 Codex 额度需先在同一 macOS 用户下登录 Codex；统计其他工具的本地 Token 不要求先购买或登录 Codex。DeepSeek 余额需要当前已配置的 Codex / Claude / cc-switch DeepSeek 路由和可读取凭据。
3. **查看“额度监控”。** 确认剩余额度、重置时间和路由；Reset Credits 仅展示接口返回的数量与到期时间，不会自动兑换。
4. **打开“Token 看板”。** 选择时间范围，切换平台或模型查看趋势与排行。首次使用会扫描已有日志；已有缓存时先显示缓存，再后台更新。
5. **按需调整设置。** 支持简体中文 / English、登录后自动启动和手动刷新。额度约每 60 秒刷新，本地 Token 约每 5 分钟刷新；文件变化还会触发合并后的更新，界面并非逐请求实时流。

额度、余额与本地 Token 是不同指标。Token 数量不能直接换算为订阅剩余额度或实际账单金额。

## 支持哪些 AI 工具

### 平台 × 数据采集矩阵

下表把“能查剩余额度 / 余额”和“能统计本地 Token 消耗”分开列出。`—` 表示当前没有该平台的额度接口接入；Token 统计也只覆盖本机实际存在、且包含明确用量字段的日志或数据库记录。

| 平台 / 服务 | 剩余额度或余额 | Token 消耗采集位置 | 需要知道的条件 |
| --- | --- | --- | --- |
| **Codex** | ✅ 官方额度窗口、重置时间、Reset Credits | `~/.codex/sessions`、`~/.codex/archived_sessions` | 需要当前 macOS 用户已登录 Codex；认证优先读取 Keychain，旧版 `auth.json` 兼容 |
| **Claude Code** | — 官方额度暂未接入 | `~/.claude/projects` | 读取本地 Transcript 的结构化 usage；不要求 cc-switch |
| **Claude Desktop** | — | `~/.cc-switch/cc-switch.db` 的 `proxy_request_logs` | 只有 cc-switch 实际捕获的桌面请求可统计；cc-switch 未运行时可能显示未采集 |
| **WorkBuddy** | — | `~/.workbuddy/traces` | 兼容旧版 Trace 汇总和新版 generation usage；没有明确字段不纳入 |
| **Qoder** | — | `~/.qoder/logs/sessions`；`~/Library/Application Support/Qoder/SharedClientCache/cli/projects` | CLI 与 Desktop / Work 使用不同日志格式，并按请求 / 消息标识去重；不查询账户积分 |
| **Kimi CLI / Kimi Code** | — | `~/.kimi/sessions`、`~/.kimi-code/sessions` | 依赖本地会话记录 |
| **Kimi Desktop** | — | `~/Library/Application Support/kimi-desktop/daimon-share/daimon/runtime/kimi-code/home/sessions` | 只采集 `usage.record` 请求记录，不把步骤汇总重复相加 |
| **Qwen CLI** | — | `~/.qwen/projects` | 依赖本地结构化 Token 字段 |
| **千问办公** | — | `~/.qwenworkcn/logs/sessions` | 读取模型请求完成记录，不重复计入回合汇总 |
| **OpenCode** | — | `~/.local/share/opencode/storage/message`、`~/.local/share/opencode` | 通用 JSON / JSONL 解析；需要明确 usage 字段 |
| **Hermes Agent** | — | `~/.hermes` | 通用结构化记录解析 |
| **OpenClaw** | — | `~/.openclaw/agents` | 通用结构化记录解析；支持 `QUOTAMONITOR_OPENCLAW_HOME` |
| **Cursor** | — | `~/.config/tokscale/cursor-cache`、`~/Library/Application Support/Cursor/User/workspaceStorage` | 只读同步缓存或结构化工作区记录；普通聊天转录不会被当作 Token |
| **Antigravity** | — | `~/.config/tokscale/antigravity-cache` | 需要已有 tokscale 结构化缓存，QuotaMonitor 不负责生成缓存 |
| **Cline** | — | `~/.cline/data/sessions`、`~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/tasks` | 需要本地任务记录包含明确 usage 字段 |
| **Grok Build** | — | `~/.grok/sessions`、`~/.grok/logs` | 通用结构化记录解析 |
| **GitHub Copilot** | — | `~/.copilot`、`~/Library/Application Support/Code/User/globalStorage/github.copilot-chat` | 依赖本机可读取的结构化记录 |
| **Pi / Oh My Pi** | — | `~/.pi/agent/sessions`、`~/.omp/agent/sessions` | 通用结构化记录解析 |
| **Zed** | — | `~/.local/share/zed/threads` | 通用结构化记录解析 |
| **Kilo Code** | — | `~/Library/Application Support/Code/User/globalStorage/kilocode.kilo-code/tasks` | 通用结构化记录解析 |
| **MiMo Code** | — | `~/.local/share/mimocode` | 通用结构化记录解析 |
| **ZCode / GLM** | — | `~/.zcode/projects`、`~/.zcode/cli` | 通用结构化记录解析 |
| **Kiro** | — | `~/.kiro/sessions/cli`、`~/Library/Application Support/Kiro/User/globalStorage` | 通用结构化记录解析 |
| **CodeBuddy** | — | `~/.codebuddy/projects` | 通用结构化记录解析 |
| **Proma** | — | `~/.proma/agent-sessions` | 通用结构化记录解析 |
| **Reasonix** | — | `~/.reasonix/stats`、`~/.reasonix/sessions`、`~/.reasonix/projects` | 通用结构化记录解析 |
| **DeepSeek（路由 / 服务商）** | ✅ 官方账户余额、近 7 日消耗估算可用天数 | 使用各工具日志中可识别的 DeepSeek 模型 / 路由记录 | 这是跨工具的服务商维度，不是另一份平台 Token；预计天数不是余额有效期 |

路径、环境变量、统计口径和验证边界见[工具支持清单](docs/DATA_SOURCES.md)。以上“支持”表示代码已接入相应入口，不代表所有工具版本都完成真实环境验证，也不代表安装工具后一定已经产生可读日志。

### 额度与余额

| 服务 | 当前能力 | 使用条件与边界 |
| --- | --- | --- |
| Codex | 读取官方服务返回的额度窗口、重置时间及可用 Reset Credits | 需要有效本地登录；字段以服务返回为准，接口和认证格式可能随上游版本变化 |
| DeepSeek | 读取官方账户余额，估算可用天数 | 需要已识别的 DeepSeek 路由及对应凭据；预计天数由近期本地用量估算，不是余额有效期 |
| Claude 官方额度 | 尚未完成真实会员账号验证 | 当前刷新链路未接入 Claude 官方额度采集；不列为可用功能，也不据此判断上游接口是否存在 |

### 本地 Token 统计

| 类别 | 工具 | 当前条件 |
| --- | --- | --- |
| 专用解析 | Codex、Claude Code、WorkBuddy、Qoder | 读取各自本地日志；已实现针对特定结构的解析和去重，仍受版本、权限及日志完整性影响 |
| 桌面端请求记录 | Claude Desktop | 当前版本通过 cc-switch 请求日志采集；只有该链路实际记录的请求才可统计 |
| 专用事件格式 | Kimi Desktop、千问办公 | 读取本机事件日志中的请求级用量；适配依赖相应日志格式 |
| 额外工具目录 | OpenCode、Hermes Agent、OpenClaw、Cline、Kimi CLI / Kimi Code、Qwen CLI、Grok Build、GitHub Copilot、Pi / Oh My Pi、Zed、Kilo Code、MiMo Code、ZCode / GLM、Kiro、CodeBuddy、Proma、Reasonix | 已加入通用解析目录；需要存在可识别的结构化 Token 字段，未逐一完成所有版本的真实环境验证 |
| 有条件的本地缓存 | Cursor、Antigravity | Cursor 读取同步缓存或结构化工作区记录；Antigravity 读取已有 tokscale 缓存。本应用不会为它们自动生成同步缓存 |

以上描述的是本地用量适配范围，**不代表所有工具都能查询剩余额度，或装好后必然有数据**。当前不纳入豆包工作和 Trae Work；DeepSeek 是模型 / 服务商维度，不作为另一份工具用量重复相加。

具体路径、环境变量、统计口径与验证边界见 **[工具支持清单](docs/DATA_SOURCES.md)**。

## 使用前，你可能关心这些

| 顾虑 | 当前已做的处理 | 仍需了解 |
| --- | --- | --- |
| 会不会耗电、拖慢 Mac？ | 使用持久化缓存、变化文件复用、可续读日志的增量解析、合并文件事件、单实例保护和菜单栏按状态重绘；已移除历史高耗电的无限脉冲动画 | 首次扫描、大文件改写和持续生成日志仍会占用 CPU、磁盘与内存；没有跨机型长期续航数据，不承诺“零耗电”。持续异常请按安装指南排查 |
| 会不会泄露聊天或 API Key？ | 用量在本机解析，不把对话正文保存到统计缓存或上传；没有项目自建的账号、广告或遥测后端 | 解析器会读取可能含正文的日志；认证信息会用于向对应服务商发起查询。缓存含路径、模型及部分去重标识，不属于匿名数据；本项目未宣称通过独立安全审计 |
| 会消耗我的模型 Token 吗？ | 应用采集本地记录、查询额度或余额，不向模型提交生成任务 | 网络查询仍存在；AI 服务及安装时所用 Agent 的收费由各自提供方决定 |
| 会修改聊天记录、自动切换路由吗？ | 本地采集读取源日志，数据库使用只读查询；应用保存自身缓存与偏好，不自动修改工具路由或兑换额度 | Codex 官方 app-server 回退由 Codex 自己管理认证；启用登录后自动启动会新增相应系统登录项 |
| 为什么和官方账单不一样？ | 按来源处理缓存 Token、模型归一化及已知重复记录 | 只覆盖本机可读日志，不包含其他设备和未落盘请求；订阅额度规则、计费口径与 Token 总量也不同 |
| 没联网还能看吗？ | 本地日志和已有统计缓存可用于查看用量 | Codex 额度、DeepSeek 余额无法离线更新；失败后可能保留旧结果，请留意更新时间 |
| 必须给所有文件权限吗？ | 应用按定义的数据目录读取，不要求把凭据复制到聊天中 | 为读取其他工具目录，当前应用未启用 App Sandbox；文件与钥匙串访问仍受 macOS 权限控制。不要为排障盲目开启全部权限 |
| 换账号或删除日志会怎样？ | 额度根据当前可读取的认证和路由更新；可保留上一份有效统计以抵御临时读取失败 | 本地历史没有完整的多账号隔离，也不是永久备份；删除源日志后重扫可能改变总量。旧缓存不应被当作当前账号账单 |

详细数据流与凭据用途见 [隐私说明](PRIVACY.md)，启动失败、空数据和持续高占用的处理见 [安装指南](docs/INSTALL.md)。

## 当前不足与可改造方向

当前优先满足个人 Mac 上的额度观察和本地用量回看，以下能力仍有边界：

- **安装分发：** 尚无 Release 安装包；源码安装需要 Swift 6 工具链。后续可完善正式签名、公证和干净环境安装验证。
- **覆盖与准确性：** 尚无覆盖全部工具版本的兼容性测试矩阵；通用解析器不保证所有来源自动去重，部分大 JSON 和非标准字段可能跳过。
- **数据完整性：** 不支持完整的云端账单同步、跨设备汇总或多账号隔离；没有日志就无法还原相应用量。
- **易用性：** 暂无逐个数据源的可视化目录配置与启停向导；自定义目录依赖启动环境或代码调整。
- **可扩展能力：** 低额度通知、CSV 导出、预算告警、自定义供应商余额接口等可以继续开发，当前不作为内置功能提供。
- **平台与维护：** SwiftUI / AppKit 实现面向 macOS；Windows / Linux 需要移植界面和系统集成。接口与日志格式变化需要持续维护。

想增加工具、换界面或设计提醒？[定制与二次开发指南](docs/CUSTOMIZATION.md)提供代码入口、验证方法和可直接交给 Agent 的改造需求示例。

## 开发与贡献

项目使用 Swift 6、Swift Package Manager、SwiftUI 和 AppKit。

```bash
swift test
./script/security_check.sh
```

本地构建、安装到“应用程序”并启动验证：

```bash
QUOTAMONITOR_ALLOW_ADHOC=1 QUOTAMONITOR_SIGNING_IDENTITY=- ./script/build_and_run.sh --verify
```

该命令会替换已有的 QuotaMonitor 应用；有本地修改时先阅读[安装指南](docs/INSTALL.md)。公开发行需按[发布指南](docs/RELEASING.md)完成正式签名和公证。

| 目录 | 内容 |
| --- | --- |
| `Sources/QuotaMonitor/App`、`Views` | 应用入口、菜单栏、主面板 |
| `Sources/QuotaMonitor/Services` | 额度接口、本地日志和数据库解析 |
| `Sources/QuotaMonitor/Models`、`Stores` | 数据口径、聚合、缓存与刷新 |
| `Sources/QuotaMonitor/Support`、`Resources` | 公共工具、图标和中英文本地化 |
| `Tests/QuotaMonitorTests` | 解析、模型与交互规则测试 |

欢迎提交 [Issue](https://github.com/haohaozhang905-code/QuotaMonitor/issues) 或 Pull Request。说明应用版本 / 提交号、macOS 与工具版本、预期行为、实际结果和复现步骤；分享截图或样例前去除凭据与对话正文。安全问题请走 [SECURITY.md](SECURITY.md) 中的私密渠道。

贡献规范见 [CONTRIBUTING.md](CONTRIBUTING.md)。本项目为独立工具，与所列 AI 服务商无隶属关系。

## License

[MIT](LICENSE) © 2026 QuotaMonitor Contributors

# 工具支持清单与统计口径

[返回 README](../README.md) · [安装与排查](INSTALL.md) · [定制数据源](CUSTOMIZATION.md)

本页按当前仓库实现说明数据入口。表中“专用解析”表示已有针对该格式的代码，“通用适配”表示已配置路径并由通用解析器读取；两者均不等于该工具所有版本已经实机验证。当前尚无完整的跨版本兼容性矩阵。

## 额度与余额查询

| 来源 | 当前实现 | 前置条件 |
| --- | --- | --- |
| Codex | 额度接口与 Reset Credits 接口；失败时尝试 Codex app-server 的 `account/rateLimits/read` | 当前 macOS 用户下的有效 Codex 认证；回退路径需能找到兼容的 Codex 可执行文件 |
| DeepSeek | `GET https://api.deepseek.com/user/balance` | 可识别的 DeepSeek 路由及对应 API 凭据 |
| Claude 官方额度 | 当前刷新链路尚未接入采集，也未完成真实会员账号验证 | 不列为可用额度功能；本地 Claude Token 或 DeepSeek 路由结果不能代替该项验证 |

Codex 的套餐名、额度重置时间、Reset Credit 到期时间是不同字段。当前不提供 ChatGPT Plus 会员到期日；仅展示重置机会，不自动使用它们。具体窗口、次数和时间以服务返回为准。

## 专用本地来源

`~` 表示运行 QuotaMonitor 的当前 macOS 用户目录。

| 工具 | 默认位置 | 实现与条件 |
| --- | --- | --- |
| Codex | `~/.codex/sessions`、`~/.codex/archived_sessions` | 读取请求级 / 累计用量；按父子会话关系排除已知的继承历史。找不到可核对的父记录时可能不纳入相关 fork 数据 |
| Claude Code | `~/.claude/projects` | 读取本地 transcript 中的 usage；无需 cc-switch。cc-switch 中同源数据用于核对，不再加一遍 |
| Claude Desktop | `~/.cc-switch/cc-switch.db` | 当前采集入口是 cc-switch 的 `proxy_request_logs`；该链路未捕获的桌面端请求无法补算 |
| WorkBuddy | `~/.workbuddy/traces` | 兼容旧 Trace 汇总与新版 generation usage；受日志格式和读取耗时影响 |
| Qoder CLI | `~/.qoder/logs/sessions` | 专用事件解析，使用请求标识处理重复记录 |
| Qoder Desktop / Work | `~/Library/Application Support/Qoder/SharedClientCache/cli/projects` | 专用转录解析，使用消息标识处理重复记录；不查询 Qoder 账户积分 |
| Kimi Desktop | `~/Library/Application Support/kimi-desktop/daimon-share/daimon/runtime/kimi-code/home/sessions` | 专用 `wire.jsonl` 解析，采集请求级 `usage.record`；不把步骤汇总重复相加 |
| 千问办公 | `~/.qwenworkcn/logs/sessions` | 专用事件解析，读取模型请求完成记录；不重复计入回合汇总 |

Kimi Desktop 可通过 `QUOTAMONITOR_KIMI_DESKTOP_HOME` 增加目录，千问办公使用 `QUOTAMONITOR_QWEN_WORK_HOME`。Codex 认证与 Token 扫描都读取启动环境中的 `CODEX_HOME`：设置后，Token 解析器扫描该目录下的 `sessions` 和 `archived_sessions`。当前文件事件监听仍包含默认 `~/.codex` 路径，自定义根目录可依赖周期或手动刷新，不保证同样的事件触发时效。

## 通用适配与有条件缓存

以下来源必须具有本机可读取、且符合解析器预期的明确 Token 字段。仅安装软件、使用云端网页或存在普通对话文本，都不保证能获得用量。

| 工具 | 默认扫描目录 | 自定义目录环境变量 |
| --- | --- | --- |
| OpenCode | `~/.local/share/opencode/storage/message`、`~/.local/share/opencode` | `QUOTAMONITOR_OPENCODE_HOME` |
| Hermes Agent | `~/.hermes` | `HERMES_HOME` |
| OpenClaw | `~/.openclaw/agents` | `QUOTAMONITOR_OPENCLAW_HOME` |
| Cursor | `~/.config/tokscale/cursor-cache`、`~/Library/Application Support/Cursor/User/workspaceStorage` | `QUOTAMONITOR_CURSOR_HOME` |
| Antigravity | `~/.config/tokscale/antigravity-cache` | `QUOTAMONITOR_ANTIGRAVITY_HOME` |
| Cline | `~/.cline/data/sessions`、`~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/tasks` | `CLINE_HOME` |
| Kimi CLI / Kimi Code | `~/.kimi/sessions`、`~/.kimi-code/sessions` | `KIMI_CODE_HOME` |
| Qwen CLI | `~/.qwen/projects` | `QUOTAMONITOR_QWEN_HOME` |
| Grok Build | `~/.grok/sessions`、`~/.grok/logs` | `GROK_HOME` |
| GitHub Copilot | `~/.copilot`、`~/Library/Application Support/Code/User/globalStorage/github.copilot-chat` | `QUOTAMONITOR_COPILOT_HOME` |
| Pi / Oh My Pi | `~/.pi/agent/sessions`、`~/.omp/agent/sessions` | `QUOTAMONITOR_PI_HOME` |
| Zed | `~/.local/share/zed/threads` | `QUOTAMONITOR_ZED_HOME` |
| Kilo Code | `~/Library/Application Support/Code/User/globalStorage/kilocode.kilo-code/tasks` | `QUOTAMONITOR_KILO_HOME` |
| MiMo Code | `~/.local/share/mimocode` | `QUOTAMONITOR_MIMO_HOME` |
| ZCode / GLM | `~/.zcode/projects`、`~/.zcode/cli` | `QUOTAMONITOR_ZCODE_HOME` |
| Kiro | `~/.kiro/sessions/cli`、`~/Library/Application Support/Kiro/User/globalStorage` | `QUOTAMONITOR_KIRO_HOME` |
| CodeBuddy | `~/.codebuddy/projects` | `QUOTAMONITOR_CODEBUDDY_HOME` |
| Proma | `~/.proma/agent-sessions` | `QUOTAMONITOR_PROMA_HOME` |
| Reasonix | `~/.reasonix/stats`、`~/.reasonix/sessions`、`~/.reasonix/projects` | `REASONIX_HOME` |

Cursor 的普通聊天转录不作为用量来源；其结构化工作区数据也必须有可识别字段。Antigravity 依赖已有的 tokscale 同步缓存。QuotaMonitor 不负责登录或同步这些工具的云端数据，也不会自动安装 tokscale。

本表与上一表合计对应当前 `TokenPlatform` 的 24 个平台标识；Claude Code / Desktop 和 Kimi CLI / Desktop 按客户端区分，不额外算成不同平台。“24”是代码适配目录数量，不能解释为 24 个平台已完整实机验证，更不代表 24 个额度接口。

环境变量指定的是额外扫描目录，会与默认目录一起读取；相同来源、相同路径会做遍历去重。变量必须传入 QuotaMonitor 启动进程，具体方式见[安装指南](INSTALL.md)。上述名称并非每个工具上游的统一配置标准，请以本项目定义为准。

## 怎样计算 Token

- **维度：** 平台表示通过哪个工具使用，客户端区分 CLI / Desktop 等入口，模型表示日志里的实际模型，服务商 / 路由是另一维度。
- **总量：** 使用结构化字段计算输入加输出；Claude 等来源的缓存读取 / 创建量需按其字段定义归入输入侧。已有输入中的缓存不再加一次。
- **细节：** 缓存和推理 Token 按来源保留为明细，不因存在明细就重复相加。未知字段不能靠文本长度或上下文上限补估。
- **模型：** 名称规范为小写，空值、`auto`、`unknown` 归为 `unknown`。这类记录可有用量，但无法可靠归属实际模型。
- **时间：** 按本机时区形成小时 / 日期桶；缺少时间字段的部分通用记录可能采用文件修改时间，时间分布因此可能不精确。
- **去重：** Codex fork、Qoder 请求标识、Kimi / 千问的请求与回合边界有专用处理；通用适配不保证对所有复制、嵌套或汇总记录自动去重。
- **DeepSeek：** 按可识别模型 / 路由归集，模型名包含 `deepseek` 的记录会被识别为相关用量；自定义别名可能无法识别。它是跨工具子集，不能再加到全平台总量。
- **预计天数：** DeepSeek 余额除以近 7 个自然日的平均估算消耗，最多显示 30 天；受本地记录覆盖和价格配置影响，不等同于账单、实际可用期限或承诺。

## 覆盖边界

1. 本机日志不是服务商全账号账单。其他设备、网页端未落盘请求、不同 macOS 用户以及已删除记录可能缺失。
2. 当前未完整按 AI 账号隔离历史统计；切换登录后，旧本地日志仍可能参与汇总。
3. 通用解析支持部分 JSON、JSONL、日志和 SQLite 结构，不是任意数据库解析器。普通 JSON 路径仅接受不超过 32 MiB 的内容；该限制不代表所有专用解析器都有相同大小上限，也不代表内存峰值上限。
4. 多数来源有超时和取消机制；Codex 的大历史扫描使用独立处理策略。首次扫描可能较慢，超时 / 失败可能保留旧结果。网络额度同样不是无延迟状态。
5. 应用优先保留暂时不可读文件的上一份有效统计，但缓存不是永久档案；删除源文件、重建缓存或上游改格式会影响总量。
6. 当前不采集豆包工作或 Trae Work；不查询 OpenRouter、MiniMax、火山引擎、Qoder 账户积分或任意自定义兼容端点的余额，也不提供 Ollama 本地用量适配。

## 代码依据

- [工具目录与通用解析](../Sources/QuotaMonitor/Services/AdditionalLocalTokenClient.swift)
- [平台与模型维度](../Sources/QuotaMonitor/Models/TokenUsageDimensions.swift)
- [专用 Codex 解析](../Sources/QuotaMonitor/Services/CodexSessionTokenClient.swift)
- [数据刷新与聚合](../Sources/QuotaMonitor/Stores/QuotaStore.swift)
- [本地来源测试](../Tests/QuotaMonitorTests/LocalTokenSourceTests.swift)

新增适配应补充经过脱敏的真实结构、验证工具版本和针对性的测试，再更新本表。请勿仅因加入路径就将其标为“全量准确支持”。

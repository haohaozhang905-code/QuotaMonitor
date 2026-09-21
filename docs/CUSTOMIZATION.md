# 定制与二次开发

[返回 README](../README.md) · [架构说明](ARCHITECTURE.md) · [提醒机制方案](REMINDER_PRODUCT_DESIGN.md) · [数据源清单](DATA_SOURCES.md) · [贡献规范](../CONTRIBUTING.md)

QuotaMonitor 按 MIT 协议开放，你可以修改、再分发，也可以让编程 Agent 帮你完成。分发代码或软件副本时需保留许可证要求的版权与许可声明。下面的扩展方向均标注了当前状态，避免将可开发的能力误当成设置项。

## 从哪些地方改起

| 想改什么 | 当前状态与代码入口 | 验收重点 |
| --- | --- | --- |
| 改配色、字体、图表布局 | 已有界面可改：`Views/PanelTheme.swift`、`Views/MainPanelView.swift`、`Views/DropdownViews.swift` | 深浅色、长模型名、大数值、空数据和窄窗口下仍可读；图标、图表、图例色彩一致 |
| 给已有工具添加日志目录 | 部分来源已有环境变量，见支持清单 | 变量进入应用进程，默认目录与额外目录同时读取时不重复计算 |
| 增加一个新 AI 工具 | `Models/TokenUsageDimensions.swift`、`Models/DataSourceDiagnostics.swift` 的 `DataSourceCatalog`、对应来源 client 与 `Stores/QuotaStore.swift` | 有真实结构化字段；登记稳定来源 ID、名称、安装探针、能力分组和 stale 时限；AdditionalLocal 能力分组会按工具目录自动生成；明确工具 / 模型归属、时间口径、缓存与去重，补对应测试 |
| 自定义刷新周期 | 周期位于 `Stores/QuotaStore.swift`，事件合并位于 `Services/LocalTokenChangeMonitor.swift`；目前不是用户可调设置 | 平衡及时性、CPU、磁盘和服务请求频率；不要用逐秒扫描读取大历史 |
| 调整提醒规则、增加预算告警 | `ReminderRuleCatalog` 声明规则与条件；文案维护本地化资源 | 保持新鲜度、冷启动补发、周期去重和 V5 状态迁移；Token 数量不能直接当作账单费用 |
| 导出 CSV / JSON | 待开发，可基于聚合桶和展示快照导出 | 明确时间范围、字段和统计边界，只导出用户选择的统计，不带凭据或正文 |
| 增加其他服务商余额接口 | 待开发，可参考 `Services/DeepSeekBalanceClient.swift` | 先验证接口与授权方式，增加安全凭据读取、网络说明、失败处理；保留原始货币和单位 |
| 做跨设备 / 多账号汇总 | 待开发，需新增账号标识与数据合并设计 | 来源身份、重复记录、同步冲突、隐私与用户授权，不直接相加每台机器的累计快照 |
| 移植到 Windows / Linux | 待开发；当前界面和系统入口依赖 SwiftUI / AppKit | 日志路径、认证存储、后台监听、图形界面和安装分发均需重新适配 |

表中源码路径均相对于 [`Sources/QuotaMonitor`](../Sources/QuotaMonitor)。

## 可直接发送给 Agent 的需求

### 新增工具的数据源

> 请在 QuotaMonitor 中增加【工具名称】的本地 Token 统计。先阅读 README.md、docs/DATA_SOURCES.md 和现有解析器，检查该工具是否存在明确的请求级 Token、模型、时间与标识字段。只读取核对所需的最小本地样例，不把完整会话或凭据发到外部。先报告可行性和统计口径；有足够证据再实现，沿用平台 / 模型分离、增量缓存和失败保留机制，补充有针对性的测试与支持清单。若只能获取文本长度、上下文上限或无法区分的汇总数字，请标明不足，不把它们估成精确 Token。

### 改界面

> 请将 QuotaMonitor 的【指定区域】调整为【风格或需求】。沿用现有信息结构与统计口径，统一图表、图例和平台图标的颜色。检查长模型名、大数值、空数据及 Hover 靠近边缘时的展示，提供修改前后截图。不要为界面占位编造用量。

### 扩展提醒规则

> 请基于 `docs/REMINDER_PRODUCT_DESIGN.md` 扩展 QuotaMonitor 的【提醒规则】。普通阈值规则只新增 `ReminderRuleCatalog` 定义、中英文文案和测试；仅在引入新条件种类时扩展执行器。复杂状态沿用对应 condition 与规则 ID 状态，任何持久语义变化都要提供 V1～V5 的顺序迁移和回归测试。保留数据新鲜度、30% / 5% 分档、补充周期去重、用户离席静默和通知降级；被环境抑制的候选事件不能提前写成已投递。规则改动不要修改状态栏创建、Bundle ID、登录项或安装流程。

## 组件边界与改动入口

| 需求 | 优先入口 | 需要保持的兼容性 |
| --- | --- | --- |
| 新增或调整普通提醒规则 | `ReminderRuleCatalog` 定义、中英文 `Localizable.strings`、规则测试 | 稳定规则 ID、条件新鲜度、去重 occurrence 和固定顺序 |
| 新增条件种类或持久状态 | `ReminderCondition` 执行器、`ReminderRuleState` 与 V1～V5 顺序迁移测试 | 失败刷新不覆盖基线、旧账本可回滚、不同规则状态隔离 |
| 修改本地 Token 扫描共性 | `Services/LocalTokenScanSupport.swift` | 保留客户端缓存版本、根目录隔离、追加读取边界和 last-good 行为 |
| 修改单个平台解析 | 对应的专用 Token client | 解析字段、fork/请求去重和 Token 口径留在来源客户端 |
| 增加 Token 来源 | `DataSourceCatalog` 的 `DataSourceDescriptor`、`QuotaStore` 的 `TokenSourceDescriptor`、对应解析器与支持清单 | 稳定来源 ID、安装探针、历史快照 V2→V3 兼容、缓存路径和平台/客户端维度；普通本地来源复用 `.local` 应用分支 |
| 修改主面板页面 | `Views/OverviewPageView.swift`、`TokenPageView.swift`、`SettingsPageView.swift` | 页面状态继续由 `MainPanelView` 协调；图表交互复用 `TokenChartViews.swift` |
| 修改系统状态栏入口 | 单独任务检查 `App/QuotaMonitorApp.swift` 与 `script/app_config.sh` | 禁止 `.autosaveName`；保持 Status4 Bundle ID；修改后做真实 Control Center 状态栏验收 |

## 推荐修改流程

1. 先检查 `git status`，保存现有修改；在独立分支或副本中进行改造。
2. 将目标写成可检查的行为，例如“同一请求出现两份副本时只计一次”，再修改对应模块。
3. 数据源改动至少验证：正常记录、缺失字段、追加写入、重复记录、文件临时不可读和缓存重载。特定场景按风险增加测试。
4. 运行 `swift test` 和 `./script/security_check.sh`。界面变动还需查看真实应用，静态测试不能代替视觉验收。
5. 用安装指南的本地 ad-hoc 路径构建验证；公开分发时按发布指南使用 Developer ID 签名和 Apple 公证。
6. 更新 README / 支持清单，明确哪些实际可用、哪些只有代码适配、哪些待真实环境验证。

完整源码入口：[Services](../Sources/QuotaMonitor/Services)、[Models](../Sources/QuotaMonitor/Models)、[Stores](../Sources/QuotaMonitor/Stores)、[Views](../Sources/QuotaMonitor/Views)、[Tests](../Tests/QuotaMonitorTests)。

## 提交反馈时提供什么

- 应用版本或提交号、macOS 版本与芯片、目标 AI 工具版本。
- 预期结果、实际结果、时间范围和可重复操作步骤。
- 已脱敏截图，或只含必要结构化字段的最小样例；高资源占用问题可补充持续时长和日志体量。

不要公开提交 API Key、认证文件、Keychain 导出、完整会话或原始缓存。额度及凭据方面的安全问题请使用[安全策略](../SECURITY.md)中的私密渠道。

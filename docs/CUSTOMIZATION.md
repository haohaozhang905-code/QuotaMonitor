# 定制与二次开发

[返回 README](../README.md) · [数据源清单](DATA_SOURCES.md) · [贡献规范](../CONTRIBUTING.md)

QuotaMonitor 按 MIT 协议开放，你可以修改、再分发，也可以让编程 Agent 帮你完成。分发代码或软件副本时需保留许可证要求的版权与许可声明。下面的扩展方向均标注了当前状态，避免将可开发的能力误当成设置项。

## 从哪些地方改起

| 想改什么 | 当前状态与代码入口 | 验收重点 |
| --- | --- | --- |
| 改配色、字体、图表布局 | 已有界面可改：`Views/PanelTheme.swift`、`Views/MainPanelView.swift`、`Views/DropdownViews.swift` | 深浅色、长模型名、大数值、空数据和窄窗口下仍可读；图标、图表、图例色彩一致 |
| 给已有工具添加日志目录 | 部分来源已有环境变量，见支持清单 | 变量进入应用进程，默认目录与额外目录同时读取时不重复计算 |
| 增加一个新 AI 工具 | `Models/TokenUsageDimensions.swift`、`Services/AdditionalLocalTokenClient.swift`；特殊格式另建专用 client 并接入 `Stores/QuotaStore.swift` | 有真实结构化字段；明确工具 / 模型归属、时间口径、缓存与去重，补对应测试 |
| 自定义刷新周期 | 周期位于 `Stores/QuotaStore.swift`，事件合并位于 `Services/LocalTokenChangeMonitor.swift`；目前不是用户可调设置 | 平衡及时性、CPU、磁盘和服务请求频率；不要用逐秒扫描读取大历史 |
| 添加低额度提醒、预算告警 | 待开发，可基于额度快照与系统通知实现 | 用户主动启用、阈值可配置、通知去重、数据过期不误报；Token 数量不能直接当作账单费用 |
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

### 开发额度提醒

> 请为 QuotaMonitor 增加可选的 Codex 低额度通知。由用户主动启用并设置阈值，仅在有效的新数据跨过阈值时提醒，避免每次刷新重复通知；额度恢复后允许下一轮提醒。数据缺失或过期时不推断余额已耗尽。说明权限和设置入口，补充阈值跨越、刷新失败及通知去重的验证。

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

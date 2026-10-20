# 需求追踪矩阵

本文件把产品需求连接到技术实现、自动测试和真实验收。状态以对应 Spec 的 `acceptance.md` 为准。

## 导航与下拉框玻璃材质

| 需求 | 产品定义 | 主要实现 | 自动化证据 | 真实验收 |
| --- | --- | --- | --- | --- |
| GLASS-001 | 下拉框随桌面变化呈现半透明模糊，信息可读 | `DropdownPopoverView`、`PanelVisualEffect` | Swift 构建、文档检查 | 浅色、深色、复杂桌面背景待验 |
| GLASS-002 | 主面板侧栏使用系统模糊材质；右侧顶部与正文同色并支持窗口拖拽 | `MainPanelView`、`PanelTitlebarDragSurface`、`MainPanelController` | Swift 构建、文档检查 | 侧栏视觉已运行检查；拖拽位移待用户确认 |
| GLASS-003 | 侧栏选中项为实色；减少透明度时下拉框与侧栏回退实色 | `MainPanelView`、`GlassSurface` | Swift 构建、文档检查通过 | 选中态、减少透明度待验 |
| GLASS-004 | 分段选择与设置开关恢复原实色样式 | `PanelSegmentedControl`、`SettingsPageView` | Swift 构建、文档检查通过 | 分段选择、开关、禁用及辅助功能待验 |
| GLASS-005 | 内容画布、卡片、图表提示与提醒卡恢复原实色样式 | `MainPanelView`、`TokenPageView`、`SettingsPageView`、`ReminderToastView`、`ChartTooltip` | Swift 构建、文档检查通过 | 浅深色、复杂桌面下的实色表面待验 |

规范与验收见 [`specs/002-glass-surfaces`](../specs/002-glass-surfaces/spec.md)。

## 提醒机制 V1.1

| 需求 | 产品定义 | 主要实现 | 自动化证据 | 真实验收 |
| --- | --- | --- | --- | --- |
| REM-001 | 额度 30%/5% 分档与跨界面颜色统一 | `QuotaRiskPolicy`、`QuotaHealth`、`ReminderRuleCatalog`、`ReminderTone` | 阈值、四舍五入、重置时间无关、跨档、冷启动与提醒 Tone 测试 | 下拉框、概览与提醒卡浅深色待完整复验 |
| REM-002 | 额度按时/提前重置，连续 100% 时间后移静默 | `quotaWindowChange`、恢复边沿状态、旧窗口 occurrence | 首次观测、休眠越窗、真实恢复、连续 100% 后移、重启与同批合并测试 | 当前安装 App 待验 |
| REM-003 | 主动重置抑制 | 重置机会数量与双额度组合判断 | 同轮新鲜请求与抑制测试 | 当前真实账号场景待验 |
| REM-004 | 重置机会到期 | `expiryWindow`、individual occurrence | 单个、多个、同时间、过期测试 | 系统通知与多卡片待验 |
| REM-005 | DeepSeek 余额 | `balanceHysteresis` | 路由、币种、触发与恢复线测试 | 当前真实余额场景待验 |
| REM-006 | Token 里程碑 | `periodMilestone`、`TokenRefreshWakeupState` | 精确 2 亿、跨多档、次日重置、首事件定时与扫描后补刷测试 | 提醒延迟需当前安装 App 复验 |
| REM-007 | 新鲜度与冷启动 | `Observed`、`ReminderContext`、Coordinator、并行额度刷新 | 缺失、失败、过期、冷启动与刷新唤醒测试 | 启动及网络刷新时序待持续观察 |
| REM-008 | 去重与持久化 | `ReminderRuleState`、`ReminderRuleLedger` V5 | 重启、漂移、周期恢复、V1～V4→V5 迁移测试通过 | 升级安装路径待持续观察 |
| REM-009 | 投递、降级与提醒卡体验 | `ReminderDeliveryController`、`ReminderToastView`、`ReminderSettings`、`PanelTheme` | 授权偏好、本地化测试与设计文档门禁 | 系统通知、深浅色、多屏待验 |
| REM-010 | 安全与副作用 | 测试提醒隔离、状态栏保护边界 | `security_check.sh`、设置与账本测试 | 安装、登录项和状态栏回归待验 |
| REM-011 | 熄屏、睡眠和锁屏静默，解锁后只判断最新数据 | 可交互状态监测器、提醒协调器、投递门控 | 状态切换、异步投递竞态和抑制事件不消费账本测试通过 | 真机熄屏、锁屏、开盖和外接屏待验 |

## 文件入口

- 产品规范：[`specs/001-reminder-v1.1/spec.md`](../specs/001-reminder-v1.1/spec.md)
- 技术计划：[`specs/001-reminder-v1.1/plan.md`](../specs/001-reminder-v1.1/plan.md)
- 任务证据：[`specs/001-reminder-v1.1/tasks.md`](../specs/001-reminder-v1.1/tasks.md)
- 验收记录：[`specs/001-reminder-v1.1/acceptance.md`](../specs/001-reminder-v1.1/acceptance.md)
- 项目级设计规范：[`docs/DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md)
- 规则与账本：[`Sources/QuotaMonitor/Models/ReminderModels.swift`](../Sources/QuotaMonitor/Models/ReminderModels.swift)
- 规则测试：[`Tests/QuotaMonitorTests/ReminderRuleTests.swift`](../Tests/QuotaMonitorTests/ReminderRuleTests.swift)

## 更新规则

- 新增、删除或改变需求语义时，先更新 Spec 和需求 ID；
- Plan 增加对应实现与迁移；
- 代码和测试完成后更新自动化证据；
- 只有真实应用验收完成后，才能更新真实验收状态；
- 被取消的需求保留 ID，并标记取消原因，避免编号复用。

## Codex 压缩历史日志兼容

| 需求 | 产品定义 | 实现 | 自动化证据 | 真实验收 |
| --- | --- | --- | --- | --- |
| HIST-001 | 普通与压缩日志均进入累计 | `CZstd`、`JSONLReader`、`CodexSessionTokenClient` | 压缩块、校验和、连接帧与长行测试 | 安装版累计起点、历史柱状图及重启后恢复均实见 |
| HIST-002 | 副本与 fork 不重复 | 会话 ID、逻辑路径、文件名关联去重；父 usage 前缀 | 双格式、跨目录、缺失身份及混合 fork 测试 | 正式缓存会话 ID 唯一；今日以前逐日摘要与冷扫一致 |
| HIST-003 | 源文件只读 | 内置流式解码；独立缓存 | 源文件内容/修改时间断言 | 全部压缩源 SHA-256、大小与修改时间检查通过 |
| HIST-004 | 格式转换、旧缓存校准及错误保守 | 可选格式/revision 标志；禁用压缩游标；last-good | V5 兼容、旧偏大缓存重算、重载、格式往返及错误测试 | 旧缓存 186,539 Token 偏差已校正，安装及重启后与冷扫一致 |

规范与验收见 [`specs/003-compressed-codex-history`](../specs/003-compressed-codex-history/spec.md)。

## WorkBuddy JSONL Trace 兼容

| 需求 | 产品定义 | 实现 | 自动化证据 | 真实验收 |
| --- | --- | --- | --- | --- |
| WBT-001 | JSON 与 JSONL Trace 都进入统计 | `WorkBuddyTraceClient` 文件发现 | 双格式 fixture 与原有 WorkBuddy 测试 | 本机 105 个 Trace 只读扫描，最近日期恢复 |
| WBT-002 | 只统计明确 generation usage | 现有定向分块解析 | usage、跨块及假标记测试 | 本机 JSONL generation 结构核对并解析 |
| WBT-003 | 格式切换不重复，缓存完整重建 | `traceId` 去重、JSONL 优先、V3 cache | 双副本 fixture | 本机现有 105 个 `traceId` 唯一；安装缓存含 105 个条目且无旧 V2 遮蔽 |
| WBT-004 | 源文件只读，重复扫描稳定 | 文件指纹缓存与独立聚合 | WorkBuddy 测试 | 今日以前结果一致，源 SHA-256、大小、修改时间不变 |

规范与验收见 [`specs/004-workbuddy-jsonl-traces`](../specs/004-workbuddy-jsonl-traces/spec.md)。

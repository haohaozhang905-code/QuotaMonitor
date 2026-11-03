# 需求追踪矩阵

本文件把产品需求连接到技术实现、自动测试和真实验收。状态以对应 Spec 的 `acceptance.md` 为准。

## 模型排行过滤零用量

| 需求 | 实现 | 自动化证据 | 真实验收 |
| --- | --- | --- | --- |
| RANK-001 | `QuotaPresentationSnapshot.breakdown` 模型排行过滤 | 混合用量、全部为零与时间窗口测试通过 | 安装版概览今日排行已核对；下拉框和其他时间范围待验 |
| RANK-002 | 保留 `TokenSourceSnapshot` 与原始请求记录 | 零用量桶保留与总量测试通过 | 本次安装未修改原始请求记录 |
| RANK-003 | 下拉框、概览和 Token 看板共用展示快照 | 模型展示快照测试通过 | 概览已核对，Token 看板可打开；下拉框待验 |

规范见 [模型排行过滤零用量](../specs/008-model-ranking/spec.md)。

## 状态栏点击态与下拉动画

| 需求 | 实现 | 自动化证据 | 真实验收 |
| --- | --- | --- | --- |
| INTERACT-001 | 系统状态栏按钮 | 构建通过 | 用户确认交互正常；加载刷新待验 |
| INTERACT-002 | 系统 `NSPopover` | 构建通过 | 用户确认交互正常；减少动态效果待验 |
| INTERACT-003 | `NSPopover` 关闭与打开 | 构建通过，竞态待运行验证 | 连续点击和动作跳转待验 |
| INTERACT-004 | 复用现有 `DropdownPopoverView`，系统提供外框 | 构建通过 | 用户确认旧白边消失、内容完整；边缘和多屏待验 |

规范见 [状态栏点击态与下拉动画](../specs/007-status-interaction/spec.md)。

## Codex 状态栏双额度

| 需求 | 实现 | 自动化证据 | 真实验收 |
| --- | --- | --- | --- |
| MENU-001 | `MenuBarSlotsView`、`QuotaMonitorApp` | 独立数值和缺失测试通过 | 用户提供的截图显示上方 71% 与下方 16%，与下拉框两项一致 |
| MENU-002 | 路由及辅助功能描述 | 全量测试及安全检查通过 | 菜单栏点击和辅助功能待验 |
| MENU-003 | 双行布局 | 多状态视图渲染和高度测试通过 | 用户截图显示新顺序；异常状态与不同菜单栏背景待验 |

规范见 [Codex 状态栏双额度](../specs/006-codex-menu-quotas/spec.md)。

## 后台能耗优化

| 需求 | 实现 | 自动化证据 | 真实验收 |
| --- | --- | --- | --- |
| ENERGY-001 | `TokenRefreshWakeupState`、30 秒事件合并 | 首事件及扫描后补刷状态测试 | 安装版刷新间隔和提醒待验 |
| ENERGY-002 | `CodexSessionTokenClient` 文件身份缓存 | 压缩、格式切换、追加、去重和缓存测试 | 真实运行能耗对照待验 |
| ENERGY-003 | `QuotaStore.totalTokenHistory` 缓存失效 | 汇总变化、提醒规则测试 | 安装版 Token 与提醒待验 |

规范见 [后台能耗优化](../specs/005-energy-efficiency/spec.md)。

## 导航与下拉框玻璃材质

历史 GLASS-001 和 GLASS-003 中下拉框自绘材质及回退实现已由 [INTERACT-004](../specs/007-status-interaction/spec.md) 替代；以下记录保留当时的追踪结果，侧栏相关要求继续有效。

| 需求 | 产品定义 | 主要实现 | 自动化证据 | 真实验收 |
| --- | --- | --- | --- | --- |
| GLASS-001 | 下拉框随桌面变化呈现半透明模糊，信息可读 | 原自绘材质已替代；现由系统 `NSPopover` 提供 | 原 Swift 构建、文档检查 | 最新实现见 INTERACT-004 |
| GLASS-002 | 主面板侧栏使用系统模糊材质；右侧顶部与正文同色并支持窗口拖拽 | `MainPanelView`、`PanelTitlebarDragSurface`、`MainPanelController` | Swift 构建、文档检查 | 侧栏视觉已运行检查；拖拽位移待用户确认 |
| GLASS-003 | 侧栏选中项为实色；减少透明度时的回退 | 侧栏 `MainPanelView`、`GlassSurface`；下拉框由系统处理 | 原 Swift 构建、文档检查通过 | 选中态、减少透明度待验 |
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

## DeepSeek Harness（QMT-009）

| 需求 | 实现 | 验证状态 |
| --- | --- | --- |
| DSH-001 | `AdditionalLocalTokenClient.parseDeepSeekHarness` | 事件及流式镜像去重测试；本机扫描已核对 |
| DSH-002 | `isCurrentHarnessGeneration` | 版本选择和 seeded 跳过测试 |
| DSH-003 | 消息 ID、事件时间和模型字段 | 自动化及本机扫描；安装应用待验证 |
| DSH-004 | 文件缓存与内置 Zstandard 读取 | 追加、缓存重载和压缩读取失败测试 |

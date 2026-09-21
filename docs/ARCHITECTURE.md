# 架构与改动边界

[返回 README](../README.md) · [提醒机制方案](REMINDER_PRODUCT_DESIGN.md) · [定制指南](CUSTOMIZATION.md) · [贡献规范](../CONTRIBUTING.md)

本文记录关键数据流与容易发生回归的边界。组件拆分用于让职责更清楚，不改变现有额度、Token 统计口径、缓存路径或用户可见提醒行为。

## 主数据流

```text
本地文件 / 服务端额度接口
          │
          ▼
来源客户端与 LocalTokenScanSupport
          │  解析、缓存、last-good、超时与取消
          ▼
QuotaStore 来源运行状态 + TokenSourceDescriptor + TokenUsageBucket
          ├─────────────────────────────┐
          ▼                             ▼
展示快照 / 页面模型               ReminderContext
                                        │ 新鲜度观察值
                                        ▼
                            ReminderRuleCatalog / 条件执行器
                                        │ 去重 + 排序
                                        ▼
                             ReminderRuleEvaluator
                                        │ ReminderRuleLedger V5
                                        ▼
                             ReminderCoordinator
                                        │ 按文案描述本地化渲染
                                        ▼
                         ReminderDeliveryController
                       系统通知 / 8 秒应用内卡片 / 跳转
```

## 主要组件

| 层 | 入口 | 责任边界 |
| --- | --- | --- |
| 来源采集 | `Services/*TokenClient.swift`、`Services/AdditionalLocalTokenClient.swift` | 保留各平台日志字段、模型与请求身份解析；来源业务语义不合并 |
| 扫描公共件 | `Services/LocalTokenScanSupport.swift` | 版本缓存容器、根路径检查、文件指纹、目录枚举、追加读取边界、模型桶生成；快照型 actor 共用 `LocalTokenSnapshotProviding` 读取包装 |
| 额度聚合与健康 | `Stores/QuotaStore.swift`、`Models/DataSourceDiagnostics.swift` | 额度展示快照、按稳定 ID 保存的来源运行状态、能力分组与安装探针目录 |
| Token 来源编排 | `Stores/QuotaStore+TokenSources.swift` | 并行刷新、超时、进度、文件变更唤醒、V2/V3 Token 快照迁移与 last-good 状态应用 |
| 提醒规则 | `Models/ReminderModels.swift` | 规则目录、条件执行器、规则 ID 状态、去重和 V5 账本迁移 |
| 提醒编排 | `Services/ReminderCoordinator.swift` | 从 Store 组装新鲜度上下文、渲染通用文案描述和读写 V5 账本 |
| 提醒投递 | `App/ReminderDeliveryController.swift`、`Views/ReminderToastView.swift` | 系统通知、应用内卡片、消失时序和点击跳转 |
| 页面 | `Views/MainPanelView.swift`、`OverviewPageView.swift`、`TokenPageView.swift`、`SettingsPageView.swift` | 主入口负责窗口与页面切换，各页面独立维护布局 |
| 图表交互 | `Views/TokenChartViews.swift` | 共用 hover / 键盘选择 / 固定状态和 tooltip 尺寸状态 |

新增普通阈值提醒只登记 `ReminderRuleCatalog` 定义、两种语言文案和测试；只有新增条件种类时才扩展 `ReminderCondition` 执行器。账本按规则 ID 保存状态，修改持久语义时必须迁移并保留 V1～V4 旧键。

新增普通本地 Token 来源时，在 `DataSourceCatalog` 登记稳定 ID、展示名、安装探针、能力分组和 stale 时限，在来源 client 保留专用解析，再把刷新操作加入 `QuotaStore` 的 `TokenSourceDescriptor`。普通快照由通用 `.local` 结果分支应用，不需要增加新的结果枚举分支；AdditionalLocal 来源的能力分组仍由工具目录动态生成。任何来源新增或改名都要检查 V2 Token 快照迁移、原缓存路径、来源健康状态及聚合口径。

`DataSourceDescriptor.installationProbe` 集中声明目录或路由型安装证据；扫描记录能否单独证明产品仍安装由 descriptor 的策略字段控制。Qoder 特意不把历史 Token 记录当作安装证据，因为卸载应用后可能保留历史日志目录。

## 状态栏与应用身份是保护边界

系统菜单栏入口由 `Sources/QuotaMonitor/App/QuotaMonitorApp.swift` 的 AppDelegate 创建。普通提醒、Token 或页面改动不应修改该入口、Dock / 登录项管理或安装替换流程。

- 当前 Bundle ID 为 `com.cmsjcm.QuotaMonitorStatus4`，集中声明在 `script/app_config.sh`；组装、开发启动与发布脚本读取同一配置。
- 禁止设置 `NSStatusItem.autosaveName`。Control Center 可能记住 blocked 状态，使“进程还在、状态栏却消失”的问题跨重启持续存在。
- `script/verify_refactor.sh`、`script/security_check.sh` 做源码保护和构建测试；只有真实运行后检查 Control Center 日志，并在桌面上看到图标与下拉框，才算状态栏视觉验收。
- 如需改状态栏或 Bundle ID，单独拆分改动、取得安装授权并执行完整真实应用验收；构建通过不代表菜单栏状态项已显示。

# QuotaMonitor 代码改造计划

版本：v1

依据：`docs/design-spec.md` v4

目标：将当前 SwiftUI 菜单栏应用改造成与 `QuotaMonitor 改造版.html` 一致的可维护实现，同时统一下拉框、主面板和菜单栏的数据口径。

## 1. 改造范围

### 本次包含

- 菜单栏状态项
- 下拉框
- 主面板窗口与标题栏
- 侧栏导航和数据源状态
- 概览页
- Token 看板
- 设置页
- 平台/客户端/模型/路由的数据聚合
- 浅色/深色主题 token
- 加载、空态、错误、未连接、额度未读取状态
- 中英文文案和相关测试
- 启动快照、来源级渐进刷新与增长 JSONL 增量解析
- 下拉框、主面板和共享分段控件动效

### 本次不包含

- 新增数据源
- 改变 Codex、Claude、DeepSeek、WorkBuddy 的 Token 统计口径
- 重写现有路由探测器
- 改变 Token 总量的基础计算口径
- 引入第三方 UI 框架

## 2. 当前代码地图

| 责任 | 当前文件 | 当前问题 | 目标 |
|---|---|---|---|
| 主面板 | `Sources/QuotaMonitor/Views/MainPanelView.swift` | 页面、主题、数据计算、组件全部集中；文件中还存在未使用的第二套 UI 实现 | 拆成页面、组件、主题和展示模型 |
| 下拉框组件 | `Sources/QuotaMonitor/Views/DropdownViews.swift` | 基础组件已有，但缺少统一状态和空态表达 | 使用统一 `DropdownSnapshot` |
| 下拉框组装 | `Sources/QuotaMonitor/App/QuotaMonitorApp.swift` | 直接在 AppDelegate 中计算和组装数据；Top 3、百分比、状态口径分散 | AppDelegate 只负责窗口/菜单动作，数据由展示模型提供 |
| 主窗口 | `Sources/QuotaMonitor/App/MainPanelController.swift` | 菜单栏应用的主面板缺少标准窗口与 Dock 找回行为 | 使用单例 `NSWindow`、智能 Dock 和统一窗口规格 |
| 额度模型 | `Sources/QuotaMonitor/Models/QuotaModels.swift` | `BalanceState` 缺少未知/未读取状态 | 增加显式 `unknown` / `connectedOnly` 语义 |
| 路由策略 | `Sources/QuotaMonitor/Models/QuotaPresentationPolicy.swift` | 已有官方/共享/不可用三态，但不能表达连接成功而额度缺失 | 扩展展示策略 |
| Token 维度 | `Sources/QuotaMonitor/Models/TokenUsageDimensions.swift` | 已定义平台、客户端、模型、提供方，UI 尚未完全复用 | 作为所有聚合的唯一维度来源 |
| 历史数据 | `Sources/QuotaMonitor/Models/TokenHistoryModels.swift` | 已有自然日填充能力，历史可用范围尚未进入 UI 状态 | 增加历史覆盖范围和空态判断 |
| 数据 Store | `Sources/QuotaMonitor/Stores/QuotaStore.swift` | 原始数据和派生数据混在 Store 中，View 仍重复聚合 | Store 输出面向 UI 的统一快照 |
| 文案 | `Sources/QuotaMonitor/Resources/zh-Hans.lproj/Localizable.strings`、`en.lproj/Localizable.strings` | 旧页面副标题和状态文案仍存在 | 按设计规范清理、补齐、统一 |
| 测试 | `Tests/QuotaMonitorTests` | 有数据源和模型测试，缺少展示口径测试 | 增加快照、状态、时间范围和百分比测试 |

## 3. 改造前置工作

### 3.1 确认真正生效的 UI 路径

`MainPanelView.swift` 当前同时包含两套设计痕迹：

- `overviewPage`、`tokenPage`、`settingsPage` 是 `body` 当前使用的页面
- `brandRow`、`balanceBand`、`summaryStrip`、`chartSection`、`tableSection`、`settingsFooter` 等实现没有进入当前 `pageContent` 路径

先建立调用关系并删除或迁移未使用实现，避免后续修改错误路径。清理过程不得改变可见行为。

### 3.2 建立基线

在改造开始前记录：

- `swift test` 当前结果
- 深色/浅色主面板截图
- 下拉框截图
- 四种路由组合的现有数据状态
- 最小窗口尺寸下的布局表现

基线用于区分视觉改造回归和原有数据源问题。

## 4. 目标架构

建议采用以下层次：

```text
QuotaStore
  ↓ 原始数据 + 刷新状态
QuotaPresentationBuilder
  ↓ 统一口径的展示快照
  ├─ MenuBarSnapshot
  ├─ DropdownSnapshot
  ├─ OverviewSnapshot
  └─ TokenDashboardSnapshot
  ↓
SwiftUI Views
  ├─ MainPanelView
  ├─ OverviewPageView
  ├─ TokenDashboardView
  ├─ SettingsPageView
  ├─ DropdownViews
  └─ Shared Components
```

### 4.1 建议新增文件

```text
Sources/QuotaMonitor/Models/QuotaPresentationModels.swift
Sources/QuotaMonitor/Models/HistoryAvailability.swift
Sources/QuotaMonitor/Views/PanelTheme.swift
Sources/QuotaMonitor/Views/Components/PanelCard.swift
Sources/QuotaMonitor/Views/Components/PageHeader.swift
Sources/QuotaMonitor/Views/Components/StatusBadge.swift
Sources/QuotaMonitor/Views/Components/QuotaCard.swift
Sources/QuotaMonitor/Views/Components/MetricStrip.swift
Sources/QuotaMonitor/Views/Components/StatePlaceholder.swift
Sources/QuotaMonitor/Views/OverviewPageView.swift
Sources/QuotaMonitor/Views/TokenDashboardView.swift
Sources/QuotaMonitor/Views/SettingsPageView.swift
```

如果拆分后的文件数量过多，可以先保留页面文件，组件文件只抽取真正复用的元素；不为了形式拆分出一次性 View。

## 5. 分阶段实施

### Phase 0：代码审计与清理

涉及：

- `MainPanelView.swift`
- `QuotaMonitorApp.swift`
- `DropdownViews.swift`

任务：

1. 标记当前实际渲染路径。
2. 移除未使用的旧版 UI 代码，或将其完整迁移到新页面组件。
3. 找出所有在 View 内直接计算百分比、Top N、时间范围和状态的地方。
4. 清理重复的主题 token 和硬编码文案。
5. 保留现有行为，先不改视觉。

完成标准：

- 编译通过
- `swift test` 通过
- 页面和下拉框可正常打开
- 没有未使用的第二套页面实现

### Phase 1：建立展示模型和状态策略

涉及：

- 新增 `QuotaPresentationModels.swift`
- 修改 `QuotaStore.swift`
- 修改 `QuotaModels.swift`
- 修改 `QuotaPresentationPolicy.swift`
- 修改 `TokenUsageDimensions.swift`

建议模型：

```swift
struct QuotaPresentationSnapshot: Sendable {
    let syncState: SyncState
    let updatedAt: Date?
    let routeSummary: RouteSummary
    let quotaCards: [QuotaCardSnapshot]
    let todayUsage: UsageSummary
    let yesterdayUsage: UsageSummary?
    let platformBreakdown: [BreakdownSnapshot]
    let modelBreakdown: [BreakdownSnapshot]
    let historyAvailability: HistoryAvailability
}

enum QuotaAvailability: Sendable {
    case loading
    case ready
    case connectedOnly
    case unavailable
    case stale
    case error
}
```

任务：

1. 把今日、昨日、近 7 日、指定周期的聚合统一放到展示模型层。
2. 将平台、客户端、模型、提供方作为互不替代的维度。
3. 统一计算百分比的分母。
4. 增加“已连接但额度未读取”状态。
5. 让 `BalanceState` 的缺失值进入 `unknown`，不能默认变成 `normal`。
6. 计算历史最早日期和各时间范围是否真实可用。
7. 为 Top N 计算补充“其他”项。

完成标准：

- 下拉框和主面板可以消费同一个快照
- 任何 View 不再自行决定统计分母
- 平台用量与模型用量可以同时出现且语义不冲突

### Phase 2：主题 token 与基础组件

涉及：

- 从 `MainPanelView.swift` 拆出 `PanelTheme`
- 新增共享组件目录

任务：

1. 建立背景、surface、border、text、品牌色和语义色的浅色/深色 token。
2. 统一字号、等宽数字、圆角、间距和阴影。
3. 抽取 `PanelCard`、`StatusBadge`、`PageHeader`、`MetricStrip`、`StatePlaceholder`。
4. 所有组件提供焦点态、禁用态和空数据态。
5. 删除无明确含义的装饰性进度线和发光效果。

完成标准：

- 主题值不再散落在页面代码中
- 页面和下拉框使用同一套语义色
- 深色模式视觉基准与改造版 HTML 对齐

### Phase 3：主面板壳层和窗口行为

涉及：

- `MainPanelController.swift`
- `MainPanelView.swift`
- 新增/拆分 `SidebarView.swift`、`TitlebarStatusView.swift`

任务：

1. 统一默认尺寸、最小尺寸和内容内边距。
2. 保留原生交通灯行为和标题栏拖拽行为。
3. 侧栏去掉顶部占位，数据源状态固定到底部。
4. 主内容保留滚动，并让滚动反馈可见。
5. 标题栏展示窗口标题和数据源更新时间。
6. 侧栏导航不再承载页面级解释文字。

完成标准：

- 980×620 默认尺寸布局稳定
- 820×540 最小尺寸不发生横向溢出
- 设置页、概览页和 Token 看板均可滚动到完整内容

### Phase 4：概览页

涉及：

- 新增或重构 `OverviewPageView.swift`
- `MainPanelView.swift` 中的 `overviewPage` 相关代码

任务：

1. 页面只保留“概览”标题，不保留标题下方副标题。
2. 实现今日 Token 主指标和较昨日标签。
3. 标签只包裹自身文字，不填满剩余网格空间。
4. 删除黄色比较线。
5. 统计条只保留标签和值，删除值下面的重复说明。
6. 重构 Codex / Claude 额度卡：
   - 官方额度已读取
   - 已连接但额度未读取
   - 未连接
   - DeepSeek 共享余额
7. 趋势卡、平台用量、模型用量全部使用 `OverviewSnapshot`。

完成标准：

- 概览不出现无法解释的颜色或进度元素
- 空额度不会显示为“正常”
- 下拉框今日数字与概览数字一致

### Phase 5：Token 看板

涉及：

- 新增或重构 `TokenDashboardView.swift`
- `TokenUsageDimensions.swift`
- `TokenHistoryModels.swift`
- `MainPanelView.swift` 中的图表和热力图代码

任务：

1. 页面只保留“Token 看板”标题。
2. 指标条使用总用量、有效日均、峰值、最高平台、最高模型。
3. 将趋势图明确为“模型类型趋势”。
4. 使用真实模型维度数据，不再通过固定比例模拟分段。
5. 图例居中。
6. 平台用量卡标注“客户端”，模型用量卡标注“模型类型”。
7. 复用 `CalendarHeatmapLayout`，让热力图填满可用宽度并显示月份刻度。
8. 时间范围不足时禁用按钮或显示空态。
9. 区分“没有数据”和“真实 0 用量”。

完成标准：

- 图表图例和排行卡表达不同维度，用户可以解释两者同时存在的原因
- 365 天热力图没有右侧大面积空白
- 30/90/累计没有用零填充伪装历史数据
- 组件在高 DPI 和最小窗口尺寸下不溢出

### Phase 6：下拉框

涉及：

- `DropdownViews.swift`
- `QuotaMonitorApp.swift`
- `QuotaPresentationModels.swift`

任务：

1. 下拉框使用 `DropdownSnapshot`，不直接读取和拼接 Store 多个字段。
2. 顶部显示今日总量、更新时间和较昨日标签。
3. 额度行复用统一的状态模型。
4. 今日平台用量以今日总量为分母。
5. Top 3 模型后追加“其他”。
6. 无数据、未连接和额度未读取均显示明确文案。
7. 保留打开主面板、刷新、设置、退出动作。
8. 根据最终视觉稿确定宽度和内容高度，避免菜单项被固定高度截断。

完成标准：

- 下拉框和主面板数字、状态、更新时间一致
- 菜单操作不会改变数据口径
- 长模型名和中英文文案不溢出

### Phase 7：设置页与本地化

涉及：

- `SettingsPageView.swift` 或 `MainPanelView.swift`
- `zh-Hans.lproj/Localizable.strings`
- `en.lproj/Localizable.strings`

任务：

1. 删除“通用”卡片标题。
2. 删除设置页页面副标题。
3. 保留开机启动和语言设置。
4. 补齐状态、空态、错误、历史不足、额度未读取文案。
5. 检查英文文本长度和动态布局。

完成标准：

- 设置页层级简洁
- 所有用户可见文本都走本地化
- 中英文切换后布局稳定

### Phase 8：测试和验收

#### 单元测试

新增或扩展：

- `QuotaPresentationPolicyTests`
- `QuotaPresentationModelsTests`
- `TokenUsageDimensionsTests`
- `HistoryAvailabilityTests`

覆盖：

- 今日/昨日比较
- 今日平台百分比
- 近 7 日模型百分比
- Top N + 其他
- 官方额度正常/低/危急/未知
- 官方路由、DeepSeek 路由、双 DeepSeek
- 空历史、部分历史、完整历史
- 刷新失败保留旧数据

#### 手动 UI 验收

- [ ] 深色模式
- [ ] 浅色模式
- [ ] 980×620 默认窗口
- [ ] 820×540 最小窗口
- [ ] 菜单栏下拉框
- [ ] 概览页
- [ ] Token 看板
- [ ] 设置页
- [ ] 点击外部关闭下拉框
- [ ] 交通灯和标题栏行为
- [ ] 键盘焦点和菜单快捷键

#### 数据组合验收

| 场景 | 需要确认 |
|---|---|
| 官方 Codex + 官方 Claude | 两张官方额度卡状态正确 |
| Codex 走 DeepSeek | Codex 卡显示共享余额和可用天数 |
| Claude 走 DeepSeek | Claude 卡显示共享余额和可用天数 |
| 双 DeepSeek | 菜单栏合并规则正确，主面板两侧状态一致 |
| Claude 未连接 | 不出现“正常”或空白状态 |
| 额度字段缺失 | 显示“额度未读取” |
| 只有近 7 日数据 | 30/90/累计不可误读为真实低用量 |
| 刷新失败 | 保留旧数据并显示过期/错误状态 |

## 6. 风险与处理

### 风险 1：当前 UI 有两套遗留实现

处理：Phase 0 先确认调用路径并清理死代码，之后再做视觉改造。

### 风险 2：Store 与 View 都在做聚合

处理：Phase 1 先建立展示快照，后续页面只消费快照。

### 风险 3：历史数据不完整

处理：增加 `HistoryAvailability`，区分缺失、空值和真实零用量。

### 风险 4：浅色模式与深色稿不一致

处理：深色稿作为第一验收基准，颜色全部通过双主题 token 管理，避免页面里直接写颜色。

### 风险 5：一次性重写主面板导致回归范围过大

处理：按“展示模型 → 共享组件 → 壳层 → 概览 → Token 看板 → 下拉框 → 设置 → 测试”顺序分阶段提交，每阶段保持可编译。

## 7. 完成定义

满足以下条件后，才认为本轮改造完成：

1. `docs/design-spec.md` 中的视觉、语义和状态规则均有对应实现。
2. 下拉框、概览和 Token 看板使用统一展示模型。
3. 平台、模型、客户端、路由没有混用。
4. 空态、错误、未连接、额度未读取和历史不足均可解释。
5. 深色/浅色、中英文、最小窗口尺寸均通过验收。
6. 单元测试和手动 UI 验收通过。
7. `MainPanelView.swift` 不再保留未使用的第二套页面实现。

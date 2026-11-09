---
id: QMT-010-PLAN
spec: QMT-010
title: 输入缓存命中展示技术执行计划
status: accepted
verification: pending
provenance: prospective
---

# 输入缓存命中展示技术执行计划

## 1. 当前证据与复用判断

本节为实施前证据记录；实施和验收现状见 tasks.md 与 acceptance.md：

- `TokenTotals` 已保留 input / cachedInput / cacheWriteInput / output；`TokenUsageBucket` 按时间、工具、客户端、模型及提供方聚合。
- `CodexSessionTokenClient` 使用累计差分并兼容压缩、fork 与内部请求回退；只有 total_tokens 的回退会借 input 承载总量，不能直接参与输入缓存率。
- `ClaudeSessionTokenClient` 把普通输入、缓存读写并入 input；当前缺字段会默认零。
- `WorkBuddyTraceClient` 已有 JSONL generation 及 trace 去重，旧 JSON 含总量回退；当前缓存字段也有默认零行为。
- `TokenUsageBucket.combining` 目前只合并数值，丢失字段是否存在的证据；不能简单在 View 做 cachedInput/input。
- 本机聚合缓存存在 Harness 的 cachedInput>input。它证明统一口径存在待核实项，不能单独证明上游字段的真实含义。

该功能是现有计数的语义补充和展示，不引入通用统计库、图表库或新的采集后端。复用专用解析器、现有聚合链、`panelCard`、`PanelTheme` 和已有格式化函数；不为一个比例新增外部依赖。价格阶段的开源算法调研与本阶段无直接实现依赖。

架构约束见 [ARCHITECTURE.md](../../docs/ARCHITECTURE.md)，视觉约束见 [DESIGN_SYSTEM.md](../../docs/DESIGN_SYSTEM.md)。

## 2. 数据流与最小模型增量

```text
已有来源读取 / 事件选择 / 去重
  → 保留原始字段存在性，核实输入语义
  → 生成有资格的缓存贡献或排除原因
  → 按小时桶和来源聚合（与原 Token 使用同一批记录）
  → 同周期、来源健康过滤与加权汇总
  → 统一 CacheUsagePresentation
  → 概览内联指标 / Token 六指标 / 既有排行条及问号弹框
```

### 2.1 字段证据与计数分开

新增小型缓存贡献模型，例如 `CacheUsageContribution`，按来源 ID、桶及资格 / 原因聚合，至少保存：

- 证据语义版本、来源稳定 ID；
- 有资格的 input、cacheRead、对应 total（I+O）；
- 不合格贡献按原因归集的 total；
- 该格式是否有明确缓存写入语义及一致性检查结果。

可作为 `TokenUsageBucket` 的新增可选成员；同桶内按 sourceID 与原因合并成有限分组，不保存请求正文或永久请求事件数组。既有桶 ID 和总 Token 计算保持不变，`combining` 显式合并贡献。使用来源 ID 是为了避免多个来源合桶后无法排除 stale 的贡献。

缺少新成员等于 `legacyEvidenceUnknown`，绝不能从默认数值推断完整证据。数值零与字段缺失的区别在解析入口保留，不能在小时桶完成后再猜。

### 2.2 来源处理

- **Codex**：在原有选中计量事件和增量逻辑旁保留证据。累计差分的前后两端须适用、字段完整、计数一致；字段中途缺失、重置或回退后，不能把重现的累计缓存量直接计入后一个小增量。缺字段边界及首次基线须用相同的原始计量范围核实，否则该段仅保留原 Token，缓存资格排除。request 与 cumulative 不重复新增贡献；total-only fallback 排除。
- **Claude Code**：在 usage 字段解析时保留存在性。校验普通输入与缓存读写，再生成 inclusive input；只有已核实格式的合法缺省才按零。缓存命中阶段不需要 TTL 或模型价格，不能把价格阶段条件搬进来。
- **WorkBuddy**：仅 generation JSONL；缓存读取必须属于被选中的 usage，不从任意文本匹配另一个 nested cached_tokens。JSONL / JSON 双副本依然只计选中副本；旧 JSON 不获得缓存资格。模型未知并不直接排除。
- **其他来源**：保留原 Token，不伪造缓存证据；当前通用来源记录为 unsupportedSource。Harness v4 经上游 usage 分桶定义核实后使用 `inputTokens + cacheReadTokens + cacheWriteTokens`；Claude Desktop 按 cc-switch 的 `input_token_semantics` 归一并按小时 / 模型 / semantics 分组。未知语义排除缓存测量。扫描读取失败的 last-good 文件需能随贡献传递降级状态，不能仅因来源有部分新结果就标全新鲜。

## 3. 汇总、状态与交互

在展示模型层新增缓存快照，由 Store 的现有展示链组装，包含：范围、input 分母、read 命中量、otherInput、ratio、coveredTotal、observedTotal、来源明细、排除原因、availability、asOf 与 partial 标志。

来源健康状态来自当前扫描结果；事件时间用于周期归属。刷新进行时展示上次快照并标更新，完成后基于同一批 Token 和健康状态发布新快照。不从 `latestUpdatedAt` 借用余额刷新时间冒充缓存读取时间。

命中率与覆盖率分别计算，零分母返回无值；不要平均已有百分比。缓存贡献跟随现有 platform/client、model 及 other 分组，保留 source/format 原因；不能因同一平台已有一个合格格式就掩盖另一个旧格式。过期贡献不参与新鲜合计，上次值在相应弹框单列。

### 3.1 页面、排行条与弹框（按用户第二轮审稿修订）

- `OverviewPageView.overviewHeroCard` 在原昨日比较与变化徽标后内联今日缓存率及问号，保留现有卡高和辅助指标。窄窗优先收紧间距，必要时缓存组整体换行。
- `TokenPageView.tokenMetricStrip` 改为六列，最后是缓存率与问号。默认 / 最小窗口检查列内边距、标题换行及模型名字号，不引入独立缓存卡。
- 为 `UsageBreakdownSnapshot` 及页面 `BreakdownItem` / `ModelRow` 传递合格 input、read、coveredTotal 和状态，不只传 total。模型排行、“其他”与平台排行用相同窗口及相同成员集合聚合。
- `rankingCard` 保留原 track 和 share 长度。在原已填充宽度内按 Rj/Tj 分配 cacheRead 子段，其余维持原类别色；右侧百分比仍是 Tj/G。绘制前保证 0≤Rj≤Tj；异常贡献排除。不得用 Rj/Ij 当填充比例，也不得因未知或极小值给蓝段设置最小可见宽度。
- 原卡片标题行加入缓存颜色图例及问号；排行行可通过点击 / 键盘打开单行说明，不新增来源表、模型筛选或缓存率排名。无证据行保留原色，通过说明区别于已核实零命中。
- 使用可复用的 SwiftUI 原生锚定 popover：概览请求 today，顶部指标与排行请求当前 dashboard period / row key。只保存当前弹框目标，不保存临时周期、不进行跨页导航。切周期关闭旧弹框。
- 弹框中保留命中量、分母、覆盖、部分 / 旧值、更新时间与排除原因；全无有效输入时指标显示 —。不为减少页面文字而把 unknown 渲染为0%。
- 计划新增 `PanelTheme.cacheRead` 语义色（待视觉验收），其他表面、字体和分隔线继续复用。具体布局、颜色与中英文文案见 [design.md](design.md)。

## 4. 需求映射与拟改位置

| 需求 | 拟改模块 | 计划验证 |
| --- | --- | --- |
| CACHE-001 | 三个专用 Token client、TokenUsageDimensions / TokenHistoryModels | 字段存在性、格式准入、累计边界、unknown 模型 |
| CACHE-002 | 缓存统计模型、QuotaPresentationModels | 加权、inclusive input、写入与输出排除、异常和边界格式化 |
| CACHE-003 | QuotaStore+TokenSources、来源健康及展示快照 | 同周期覆盖、last-good、冷启动、扫描中与失败 |
| CACHE-004 | OverviewPageView、说明 popover | 比较行内联、今日范围与开关焦点 |
| CACHE-005 | TokenPageView、说明弹框局部状态 | 六指标、当前周期、切换时关闭旧弹框 |
| CACHE-006 | UsageBreakdownSnapshot / BreakdownItem、rankingCard | 平台 / 模型 / other 分组、R/T 子段与 R/I 说明、未知和原占比保护 |
| CACHE-007 | 现有主题 / Formatters、中英文资源、上述两页 | 长英文、极值、VoiceOver、键盘与浅深色 |
| CACHE-008 | 三源缓存、TokenHistorySnapshot、combining | 旧缓存、失败重扫、追加 / 压缩 / fork / trace 去重及回滚 |

不为文案规划提前创建未使用的资源键或改 Swift 文件。实际实施时，新增共享组件仅服务本功能，不顺带重构其他图表或导航。

## 5. 实施顺序与门禁

1. **文档准备（本次）**：建立 Spec、Plan、设计说明、任务、验收空白基线和追踪项；检查链接与需求 ID。此步骤不等于功能实现。
2. **来源证据与兼容（实施中）**：从三源提取最小脱敏结构并验证缺省规则；增加存在性和资格标记、兼容读取及边界测试。不能取到某格式可靠证据时，该格式保持未纳入。
3. **汇总与来源状态**：实现纯统计模型、来源健康过滤及快照；用固定输入验证所有 Spec 算例，原 Token 回归不变。
4. **页面与本地化**：按第二轮方向实现比较行、六指标、两类排行条组成和问号 popover；同步中英文、焦点和最小窗口。旧原位展开方案不再实施。
5. **独立验收**：执行自动化、只读真实扫描、真实应用及视觉检查，各自记录；不得用文档门禁或 build 代替产品验收。安装替换需要另行授权。

阶段 A 验收完成后才评审价格阶段的独立需求；不在同一 PR 预置价格空卡、价格设置、金额字段或网络接口。

## 6. 缓存迁移与回滚

- 三个专用 client 的缓存增加证据 schema/revision；只让旧证据失效，旧数值仍可用于现有 Token 展示。
- 若外层缓存版本不兼容，先读入现有支持版本为 legacy，仅在隔离的后继缓存文件写新版本；当前版本号与路径在实施时核实，不在文档中猜下一个数字。旧文件不覆盖、不删除，以便回滚。
- 原 `TokenHistorySnapshot` 可接受新增可选贡献；必须验证旧二进制能忽略新增字段，及其重写缓存后新二进制会回到 legacy 而不会生成假零。
- 新语义首次刷新需要完整重扫相关源文件，再恢复原有追加读取。压缩源继续整文件处理；原增量指纹、fork 和 generation 选择边界保留。
- 重扫失败：原 Token 沿用 last-good，缓存信息保持未知或过期；不把部分扫描当完整新证据。
- 回滚恢复旧应用 / 代码及保留的旧缓存；新缓存留作可再生派生数据，不自动清理。原始日志保持不变，无不可逆数据迁移。未来清理旧缓存应另定保留与授权策略。

## 7. 测试、实机及视觉验收

- **逻辑**：按 Spec 算例覆盖 weighted ratio、命中率 / 覆盖率 / 条段组成的分母、I=0 / R=0 / R=I / near boundaries、R>I / R+W>I、unknown 模型、mixed evidence、total-only 回退。验证 I=100/R=80/O=100 时率80%、条内占40%，以及 other 组成员一致。
- **来源**：正常、缺字段、重复、追加、暂不可读、旧缓存和重载；Codex 累计缺字段跨界、fork 与压缩；Claude inclusive input；WorkBuddy 同 trace 双格式和 generation 对象定位。
- **状态**：同桶部分有效、来源部分 last-good、来源失败、首次 / 后续刷新、日期跨界、概览今日与看板周期分开；开关 / 切周期关闭弹框、外部点击 / Esc 和焦点恢复。
- **回归**：对固定 fixture 的原总 Token 和现有提醒结果前后比较；不修改原文件。只读集成验证采用临时目标缓存，记录扫描范围、输入摘要及源文件大小 / mtime / 必要哈希，不保存完整会话。
- **命令（实施后）**：`./script/verify_sdd_docs.sh`、针对性 `swift test`，以及仓库规定的构建 / 安全门禁；本次仅执行文档检查及文档定向审计。
- **运行与视觉**：真实应用上检查浅深色、中英文、980×620 / 820×540 pt、完整 / 部分 / 未知 / stale、Tab / Enter / Space / VoiceOver、减少动态效果。原 Token、额度、窗口和菜单栏行为回归另记。

## 8. 完成定义

所有 CACHE 需求有实现和自动化证据；三源逐个标明真实格式验证范围；界面与视觉独立通过；旧缓存迁移 / 回滚有运行证据，且保护边界无越界。待验项目保留 Pending，不提前标 verified。当前进度见 [tasks.md](tasks.md)，验收以 [acceptance.md](acceptance.md) 为准。

## 2026-11-08 交互收敛实现

移除排行 Button / popover 和 cacheRowPopover 状态，使用行 hover / focus 与 anchor preference，将小 tooltip 提升到两个排行卡共同父层；与图表复用 PanelTheme tooltip 语义色。问号组件改为定义和一条当前状态；数据采集与原因模型不变。运行既有全量测试和 SwiftUI 渲染，并在实际窗口验证问号与 hover / 键盘及未知态。

### 第二次审稿实施

根 MainPanelView 接收问号 anchor preference，在主面板坐标系内按测得浮层尺寸约束位置；排行仅通过共享 hover ID 和 anchor preference 驱动浮层及非选中行透明度。去掉排行焦点、手势、图例及 cacheRead 着色。主面板与下拉 hosting 层统一关闭 AppKit focusRing，根 SwiftUI 关闭系统 focusEffect。

## 2026-11-08 来源口径更新

- Harness 原始 `inputTokens` 是 uncached input。解析器现在归一 `TokenTotals.input` 为 uncached + read + write，并仅在 cache read、cache write、output 字段齐全且数值为非负整数时生成测量。
- cc-switch 查询读取 `input_token_semantics` 并按 semantics 分组，旧 schema 缺列时仍保留旧 Token 总量，但不提供缓存测量；未知语义不臆断。
- Desktop 成功刷新进入缓存新鲜来源集合，刷新失败则移除；其 last-good 总量继续保留，但不作为本轮新鲜缓存率证据。
- `AdditionalLocalTokenClient` 缓存版本提升到 4，旧版本 3 的解析结果失效并重扫；源会话日志只读不变。
- 排行 hover 离开后延迟 80 ms 清空，进入下一行会撤销清空任务；当前行 / 其他行的透明度通过短缓动交接。

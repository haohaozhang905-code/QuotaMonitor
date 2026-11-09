# 输入缓存命中展示验收记录

> Spec：`QMT-010`；当前结论：功能已实现并替换安装；全量逻辑、自动化检查和五个来源本机只读扫描通过。主面板窗口复查及纯鼠标相邻 hover 仍待验收。

## 文档检查（与功能验收分开）

- 2026-11-04：`./script/verify_sdd_docs.sh` 与 `git diff --check` 通过。前者主要检查既有规范基线，不能证明新增功能已实现。
- 新增定向审计：8 份相关 Markdown 的本地链接、Spec / Plan draft 元数据、模板占位及 CACHE-001～CACHE-008 在计划 / 任务 / 验收 / 追踪中的关联检查通过。新增文件另查行尾空白。
- 第二轮设计修订后，9 份相关 Markdown（含 superseded 归档）的上述关联与链接、空白检查通过；R/I=80%但R/T=40%的固定算例已核算。SDD 门禁再次通过，功能和真实视觉验收仍为 Pending。
- 首轮文档工作开始时工作区干净；第二轮在上述未提交文档上修订，并增加审稿图片。未改应用代码，旧视觉方案另存 superseded。

## 自动化验收

| 场景 | 需求 | 预期 | 证据 | 状态 |
| --- | --- | --- | --- | --- |
| 格式准入、缺失与零、total-only、累计边界 | CACHE-001 | 保留真实证据，未知不参与 | 已接入，针对性异常与真实验收仍待补充 | Partial |
| 加权、两个分母、写入 / 输出 / 推理排除 | CACHE-002 | 符合 Spec 算例且不重复 | 独立计算、三源解析与累计边界测试通过 | Partial |
| 异常、I=0 / R=0 / 边界显示 | CACHE-002 | 不 clamp、不除零、不伪造边界 | 已接入，针对性异常与真实验收仍待补充 | Partial |
| 混合覆盖、last-good、来源失败、冷启动 | CACHE-003、CACHE-006 | 正确状态及排除原因 | 已接入，针对性异常与真实验收仍待补充 | Partial |
| 今日 / 所选周期与说明弹框 | CACHE-004、CACHE-005 | 范围显式、切周期关闭旧内容 | 已接入，针对性异常与真实验收仍待补充 | Partial |
| 平台 / 模型 / other 分组条段 | CACHE-006 | 原条长和用量占比不变；蓝段按R/T，输入率按R/I，未知不当零 | 已接入，针对性异常与真实验收仍待补充 | Partial |
| 中英文资源、展示与访问状态 | CACHE-007 | 文案完整、状态可访问 | 已接入，针对性异常与真实验收仍待补充 | Partial |
| 重复、追加、压缩、fork / trace、旧缓存重扫与回滚 | CACHE-008 | 原 Token 不变、证据可再生 | 已接入，针对性异常与真实验收仍待补充 | Partial |

## 真实来源、应用与视觉验收

| 环境 / 场景 | 预期 | 构建 / 证据 | 状态 |
| --- | --- | --- | --- |
| Codex / Claude Code / WorkBuddy JSONL 逐格式扫描 | 字段语义、存在性与缓存贡献可独立复核 | Codex、Claude 本机只读扫描；WorkBuddy 目录不存在 | Partial |
| 默认 / 最小窗口、浅深色、中英文 | 内联组不抢主数字、六列不截断，图表不被新容器下推 | 审稿图和 fixture 离屏渲染；非真实 App 截图 | Pending |
| 完整 / 部分 / 无输入 / 更新 / stale / 异常 | 状态与分母不会误读 | 界面已接入，真实交互待验 | Pending |
| 问号 / 行点击、外部点击 / Esc、周期变化 | 弹框锚定、范围正确、焦点恢复、无多余持久状态 | 界面已接入，真实交互待验 | Pending |
| Tab / Enter / Space / VoiceOver、减少动态效果 | 可操作、可理解、无隐藏焦点 | 界面已接入，真实交互待验 | Pending |
| 旧缓存升级、失败恢复、回滚 | 原 Token 和源文件保持、旧版可恢复 | 独立证据缓存已实现；升级与失败恢复待实测 | Pending |

## 证据边界与剩余风险

- 来源字段证据和页面已接入；自动化测试不能证明所有实际格式与真实界面均已验收。
- 派生缓存只证明当时存储的数值，不能恢复缺字段证据或证明上游 schema。
- Harness 缓存读取大于输入尚未定位根因，本阶段只明确排除，不扩大为总量修复。
- 已运行全量测试和 fixture 离屏渲染；未安装、替换或提交应用，真实界面和用户视觉验收保留 Pending。

## 2026-11-04 实施与检查记录

- 三源字段证据、按输入加权的缓存率、按总量计算的覆盖率和 R/T 排行条段已接入；概览、六指标及问号 / 行弹框已实现。
- 完整 Swift 测试通过（Swift Testing 157 项、XCTest 18 项，含既有回归）；SDD 文档检查和安全检查通过。
- 不写正式缓存的本机扫描：Codex 676 个桶中 666 个含合格证据，Claude Code 7 个桶均含合格证据。WorkBuddy 默认目录在当前环境不存在，实扫未完成；JSONL fixture 已覆盖。数字仅为扫描时桶数量，不代表账户完整性。
- SwiftUI fixture 的概览和 Token 页面在 650 pt 内容宽度下完成离屏渲染检查；此项不是实际应用窗口、键盘交互、VoiceOver、深色或用户视觉验收。
- 待完成：排除原因的逐项区分、逐文件过期原因明细、迁移 / 失败恢复和 other 分组的针对性测试，以及真实应用、最小窗口与交互验收。不得将此记录解读为全部需求通过。

## 2026-11-08 实装及复验

- 缓存统计的排除原因已分为未接入来源、旧格式、字段缺失、异常、时间缺失、旧缓存、文件读取失败和来源不可用；解释只显示有证据的类别。
- Codex 固定 fixture 覆盖证据版本重扫、文件读取失败时保留旧总量但不纳入新鲜命中，以及文件恢复后重新统计。已有压缩 / fork / WorkBuddy 双格式回归通过；不能据此声称全部来源的物理故障迁移均已实测。
- `QMT_CACHE_RENDER=1 swift test`：Swift Testing 159 项、XCTest 18 项通过；SDD 文档、安全检查和 `git diff --check` 通过。
- 11 月 4 日实际候选窗口检查了概览、两个排行、其他模型、周期切换、点击和 Escape、Tab / 空格 / 回车、浅深色及中英文；570 pt 内容宽度另通过离屏渲染。候选二进制 SHA-256 与 11 月 8 日安装版一致。
- 11 月 8 日已替换 `/Applications/QuotaMonitor.app`，签名校验通过，实际进程从该路径启动。安装后查看概览、Token 看板、来源说明和 Escape；Codex、Claude Code、WorkBuddy 均出现缓存率，部分数据原因可见。数据随实际使用变化，不将示例数值固定为验收基线。
- 菜单栏脚本未在 Control Center 日志中找到进程初始化记录，自动核验失败；尝试读取系统界面超时，不能断言菜单栏图标可见或不可见。VoiceOver、真实 820×540 窗口和用户最终视觉验收尚未完成。
- 原安装版与替换前缓存备份位于 `.artifacts/cache-hit-install-EWJ7TrpG/`；原安装包还保留在 `/Applications/.QuotaMonitor.cache-hit-previous.49016`。回滚时先退出当前应用，再将备份应用恢复至 `/Applications/QuotaMonitor.app`；缓存备份仅在确有需要时恢复，以免覆盖此后新增用量。

## 2026-11-08 问号与排行交互精简

- 用户复审后，用短定义与一条必要状态替换长说明；原覆盖公式、来源表及原因清单不再出现在日常弹框。计算证据继续保留在来源数据中。
- 平台 / 模型排行改为 hover / 键盘聚焦浮层：名称、缓存率、部分 / 未知短状态；移除 Button、点击 popover、持久选择及蓝色系统焦点框。鼠标离开时清除行焦点，切周期重建行交互状态。
- 实际候选窗口检查了短问号、平台行浮层的显示与卡片外绘制、无蓝框；鼠标离开清除焦点的最终修订另通过编译和全量回归。
- `QMT_CACHE_RENDER=1 swift test`：Swift Testing 159 项、XCTest 18 项通过。小窗 fixture 离屏渲染和文档 / 安全检查通过。用户最终视觉验收仍由用户确认。

- 精简版本已更新至 `/Applications/QuotaMonitor.app`，签名校验及重启路径检查通过。安装版复查短说明、排行浮层和无蓝框；自动化界面工具无法单独发送 mouse-move，因此纯鼠标 hover 的进入 / 离开流转仍需用户在实际鼠标上确认，不能将点击 / 聚焦看到浮层等同为纯 hover 验收。鼠标点击不会固定查看状态，键盘焦点可单独查看。备份位于 `.artifacts/cache-hover-mmktFY4I/QuotaMonitor.before.app`。

## 第二次交互审稿验收（2026-11-08）

- 实际候选窗口中，Token 页靠右问号已在主面板内部完整显示；Escape 可关闭。排行标题右侧内容已移除，原色条形恢复；点击条目未出现焦点、按钮或弹框状态。
- 排行交互代码只监听 hover：共享当前行 ID，当前行透明度 1，其他行 0.42，与柱状图一致；小浮层仅显示缓存率、原色圆点、名称、缓存命中数量，未知显示 —。正常 / 未知浮层均已渲染检查；自动化工具不支持单独 mouse-move，纯鼠标进入 / 离开及遮罩联动仍保留用户实际鼠标验收，不能以点击当成 hover 验证。
- `QMT_CACHE_RENDER=1 swift test`：159 项 Swift Testing、18 项 XCTest 通过；后续浮层专门渲染也通过。最终构建签名、SDD、安全检查、diff 空白检查通过。
- 最终构建已替换 `/Applications/QuotaMonitor.app`，重新启动并核对 Token 页排行与入口；备份 `.artifacts/ranking-refine-JyAkjTjJ/QuotaMonitor.before.app`。
- 当前缓存来源核对：DeepSeek Harness 现有 9 个聚合桶均 cachedInput>input，未核实前不能计算比例；Claude 桌面版来自 cc-switch，数据库有缓存读取字段，但本阶段尚未接入字段证据和新鲜度链。显示 — 表示不可计算，不等于无缓存或 0%。本次未改来源准入和原总量口径。

## 2026-11-08 来源语义核验

- 本机 Harness v4 的类型与消费实现将 `inputTokens` 定义为未命中缓存输入，read/write 是独立桶；输入总量按三者相加。原“缓存读取大于 input”是把未命中桶误当成含缓存的总输入，不能据此裁剪 read 数值。
- 当前 Harness 本机只读扫描：5 个聚合桶全部有缓存证据，命中量 69,680,256，合格输入总量 70,592,420。旧 9 桶数值来自旧解析语义，Additional Local Token 缓存版本 4 会要求重扫。日志是本机会话集合，不代表账号账单完整范围。
- cc-switch 数据按 `input_token_semantics` 归一：0=raw input 已含 read、未含 creation；1=input 已含 read 与 creation；2=fresh，不含两种缓存。当前本机29条 Desktop 请求均为语义2，聚合4桶命中量664,960、合格输入707,540。
- 若旧数据库缺 semantics 列，Token 总量仍可读，缓存测量显示未知。扫描只输出汇总量，不输出请求 ID、模型列表、时间或凭据。
- 上游核对：[DeepSeek Harness usage semantics](https://github.com/deepseek-ai/deepseek-harness/discussions/8829)、[usage projection source](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/llm/token-meter/src/usage-projection.ts)、[cc-switch usage definitions](https://github.com/farion1231/cc-switch/blob/main/src/types/usage.ts)。

## 2026-11-08 Hover 字体与交互修订

- Tooltip 与 Token 图表 tooltip 统一等宽字号层级，展示“输入缓存命中率 + 比例”及“名称 + 命中 Token/输入 Token”。
- 行离开事件延迟 80 ms 清除，进入相邻条目会取消清除并顺滑交接。纯鼠标真实界面验证仍待本轮完成。

## 2026-11-08 最终构建、来源及安装复验

- `swift test` 全量通过：160 项 Swift Testing，21 个测试套件；`./script/verify_sdd_docs.sh`、`./script/security_check.sh`（182 个可发布文件）和 `git diff --check` 均通过。
- `QMT_CACHE_LIVE_SCAN=1 swift test --filter CacheLiveScanTests/scansConfiguredSourcesWithoutPersistentCaches` 通过，使用临时缓存且未改动原始来源文件。扫描摘要：Codex 689 桶 / 679 合格；Claude Code 7 / 7；WorkBuddy 19 / 19；DeepSeek Harness 5 / 5，缓存读取 69,680,256、完整输入 70,592,420；Claude Desktop 4 / 4，缓存读取 664,960、完整输入 707,540。桶数表示本机本地会话范围，不代表账户账单完整性。
- 安装版通过 `codesign --verify --deep --strict`；从 `/Applications/QuotaMonitor.app` 启动的进程 PID 为 79201，安装二进制 SHA-256 与刚构建二进制一致：`b6d3bcb15cbe2822ca31bc5458819356196d081e1c537e1edb685ee7d03f11f9`。
- 当前旧应用保存在 `/Applications/.QuotaMonitor.previous-20261108-231608`，额外副本位于 `.artifacts/cache-hover-final-20261108-231608/QuotaMonitor.before.app`。回滚时先退出 QuotaMonitor，再把旧应用移回 `/Applications/QuotaMonitor.app`；不需要恢复缓存。
- 本轮 CUA 找到空白 `QuotaMonitor Settings` 窗口，未能从辅助功能界面进入主面板；工具不支持独立 mouse-move。因此本轮无法对已安装主面板截图、实际鼠标 tooltip 字体、相邻条目衔接或遮罩做真实窗口验收。用户对最终视觉的确认仍 Pending。
- DeepSeek Harness 的 `inputTokens` 是 uncached input，缓存读取 / 写入分别为独立桶，故读取量可大于 `inputTokens`；读取量不裁剪，输入分母按三桶求和。[Harness usage discussion](https://github.com/deepseek-ai/deepseek-harness/discussions/8829)、[usage projection](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/llm/token-meter/src/usage-projection.ts)。cc-switch 按 `input_token_semantics` 归一 raw input；未知 / 缺列时保留 Token 用量，但缓存率未知。[cc-switch usage types](https://github.com/farion1231/cc-switch/blob/main/src/types/usage.ts)、[usage view](https://github.com/farion1231/cc-switch/blob/main/src/components/usage/RequestLogTable.tsx)。

### 用户复审修订

- 根据用户反馈，移除行间 120 ms 缓动。相邻项现在立即切换；离开延迟 80 ms 仅保留状态交接保护，不产生动画。
- Tooltip 名称此前未指定字体，继承系统默认字号；现明确设为 9 pt 等宽，与图表条目字号一致。

### 问号弹框统一

- 缓存命中率与 Codex 可用重置次数使用同一 `PanelHelpButton` 和原生 popover；统一点击、无系统蓝色焦点框、点外关闭和 Escape 关闭。
- 缓存说明靠近内容栏右侧时向左展开，避免越过内容模块右边界；安装版真实界面已通过 Token 看板右侧问号复验。

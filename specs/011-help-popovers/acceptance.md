# QMV-011 验收与页面扫描记录

日期：2026-11-09。当前结论：用户第四次审稿要求的 20 pt 连续圆角已实现、检查并替换安装；帮助弹框、图表 tooltip 和缓存排行 tooltip 共用圆角 Token。此前 186 项全量回归通过；后续卡片高度与圆角为局部 UI 修改，分别完成候选构建/签名及安装版界面核对，未重跑自动化测试。安装版签名和进程哈希复核通过。用户最终视觉确认仍 Pending。当前安装与备份以文末最新记录为准。

## 自动化与构建

- 全量回归：160 项 Swift Testing、22 项 XCTest 通过，含新增 3 项原生弹框测试。
- `PanelHelpPopoverTests` 覆盖关闭状态不创建内容树、transient/no-animation 配置、未附着锚点不展示、取消待展示任务、真实 NSWindow 内打开/更新内容/关闭回写/重新打开/移除清理。
- 原生窗口测试通过 `QMT_HELP_WINDOW_TESTS=1` 显式启用，默认 CI 跳过需要桌面的场景。
- SDD、安全及 diff 空白检查通过。签名校验通过；候选是本机 ad-hoc QA 包，不能据此声称公开发布可用。
- 默认构建目录曾引用已移除的 MacOSX27.0 SDK 而失败；CLT 尝试缺 SwiftUI 宏插件。最终用当前 Xcode 的独立 `/tmp/qmt-help-xcode27-20261109` 目录成功构建及测试，未修改系统工具链配置。

## 真实候选应用检查

最终候选：`/tmp/qmt-help-review-v4-20261109/QuotaMonitor.app`。通过独立进程运行，安装目录仍是原版。复查曾使用进程环境强制深色和启动参数临时指定英文，不写入语言/外观偏好；交付恢复正常中文/跟随原设置启动。

| 需求 | 场景与结果 | 证据边界 |
| --- | --- | --- |
| HELP-001 | 三处入口均保留系统原生箭头与连续表面；浅色中文与深色英文截图已查看 | 本机当前 macOS；其他版本待验 |
| HELP-002 | 原生动画关闭，开关说明无缩放、弹跳与位移 | 配置与实际交互；未逐帧测量 |
| HELP-003 | 鼠标重复点击开关、点击其他页面关闭、Escape 关闭、周期切换关闭已检查 | 最终键盘增补后单独复查 |
| HELP-003 | Tab 到问号，space / return 打开，Escape 关闭；焦点留在问号，再次打开及 Tab 到下一入口成功 | 实际键盘路径；非 VoiceOver 朗读验收 |
| HELP-004 | 概览今日缓存、看板周期缓存、Codex 重置次数均显示完整内容；英文重置日期可换行，未截断 | 未覆盖所有语言/外观交叉组合 |

仍待验证：精确 820×540 pt 真实窗口（两次边缘拖拽未改变窗口尺寸，不能记为通过）、VoiceOver 朗读、其他屏幕边界、用户视觉确认。系统减少动态效果无需额外分支，因为本组件始终无动画；没有实际切换系统设置验证。菜单栏、系统通知、休眠唤醒与长时间能耗不在本次真实运行验收范围。

## 首轮页面扫描发现（后续已修复）

检查了概览、Token 看板、设置的真实界面及相关源码，也检索了下拉框与图表交互。以下均独立于本次公共弹框修复：

| 优先级 | 发现 | 证据与影响 | 建议 |
| --- | --- | --- | --- |
| P2 | 排行的辅助功能值只剩缓存率 | `CacheRowInspection` 使用 children: .ignore，重写 value 只保留缓存率；实际 AX 树也只显示名称和命中率，原 Token 用量/占比未提供 | 已修复：静态摘要补回 Token / 占比，保留用户确认的 hover 规则和无行按钮交互 |
| P2 | 悬停更新路径存在重复汇总 | `tokenMetricStrip` 重复两次 cacheBuckets/cacheSummary；两个排行的每一行再次筛选整个周期集合。hoveredUsageRow 属于 MainPanelView 状态，更新会进入页面重算路径 | 已修复：周期快照和平台 / 模型分组共用一次汇总；hover 状态局限于排行组件。固定 2 万桶样本对照通过；未据此推断整机帧率或长期 CPU |
| P3 | 设置页将不支持能力渲染成红色失败 | 实际“额度：未提供来源”“Token：未提供来源”显示红字/红叉；`capabilityCell` 和原因统一使用 danger | 已修复：区分未提供来源、无记录、未检测、扫描、警示与刷新失败；仅失败使用失败色 |

没有以本次短时操作推断整个应用无性能问题；尚未进行 Instruments、持续能耗或大规模日志压力测试。

## 运行与回退

可从候选包查看本次结果。安装版未覆盖，关闭候选后重新打开 `/Applications/QuotaMonitor.app` 即回到原安装版，无需恢复缓存。若回退代码，仅撤销本次 `PanelHelpButton.swift`、说明颜色及相关文档差异，不要还原整个脏工作区。

## 2026-11-09 用户复审完成记录（覆盖首轮形态及未安装状态）

### 已实现

- 撤销系统灰色 NSPopover 外壳，改为无边框、无阴影的 nonactivating child NSPanel；近白 #FAFAFB / 深色 #1E1F24，正文与箭头用单一 Shape 连续填充，无放大/位移。问号无新增点击/焦点底色。
- 仅显示时挂载鼠标、Escape、滚动和父窗口生命周期监听；外部点击、页面/周期切换、窗口关闭/移动/缩放/失焦清理。限定父窗口及屏幕可见范围。
- 排行静态辅助摘要补回原用量、占比和缓存率，中英文同步；没有增加行按钮、点击固定或键盘聚焦。
- CacheUsageSnapshot 统一准备周期总计与平台/模型/other 分组；指标复用 total，排行状态移到 CacheRankingInteraction，hover 不使主页面重新执行周期筛选和汇总。
- 设置能力状态明确区分未提供来源、无日志、未检测到、扫描、权限、格式、过期、失败。正常缺失使用中性色减号，扫描使用中性色循环箭头，警示使用暖色感叹号，仅失败使用红叉；原因按各自状态独立着色。

### 自动化与运行证据

- 164 项 Swift Testing、22 项 XCTest 通过。新增 4 项缓存/来源展示回归，原生 child panel 的无边框/无阴影/无动画、内容更新、关闭回写、重开与清理测试通过。原生窗口附加断言验证 panel.parent 为触发窗口且 frame 位于父内容区域。
- 20,000 桶固定样本与旧逐模型筛选算法对照一致；批量汇总约 0.014785 秒（本机 debug 单次样本，无整机帧率或长期能耗结论）。
- SDD、安全、diff 空白检查通过；双语资源 365 个键完全匹配。
- 真实候选查看了浅色中文三处说明和深色英文说明；实际键盘打开/Escape、重复点击、周期及页面切换检查。已安装主面板复查了新说明、Escape、页面切换、完整排行 AX 摘要和中性来源能力图标。
- CUA 只返回当前主窗口的 AX 树；辅助说明子 panel 未进入该主窗口树。上述说明实际可见由截图确认，不能据此声称已经完成 VoiceOver 的跨窗口朗读验收。

### 安装与回滚

- 已替换 `/Applications/QuotaMonitor.app`，签名 `codesign --verify --deep --strict` 通过。实际 PID 41123 从该路径启动。安装二进制 SHA-256 与通过候选检查的包一致：`d25c8822a2cca1dab4d6462833522e9119eff37963eadc0552dd4c744d1fb0ed`。
- 完整备份：`.artifacts/help-light-install-pbvqgnfu/QuotaMonitor.before.app`。原安装包另保留在 `/Applications/.QuotaMonitor.help-light-previous-20261109-110805.app`。安装记录与哈希保存在备份目录的 installation.json 中。
- 回滚时退出当前 QuotaMonitor，将备份应用复制回 `/Applications/QuotaMonitor.app` 并重新打开；不需要恢复缓存或偏好。回滚前保留当前包，避免覆盖后续新版本。

### 待验证与边界

用户最终审美确认、精确 820×540 真实窗口、VoiceOver 朗读和实际鼠标连续 hover 流转仍 Pending。安装后菜单栏脚本未查到 PID 41123 的 Control Center 初始化日志而返回失败；该结果不能证明图标隐藏或显示，菜单栏可见性未独立验收。未改状态栏、应用身份或登录项，也未做长期能耗/系统通知/休眠唤醒验收。

## 2026-11-09 第二次视觉审稿与替换安装

### 本轮改动

- 按用户复看意见，在箭头与正文同一轮廓上增加低对比软阴影。AppKit panel 保持无系统边框/阴影，阴影为单层自绘，外围透明留白纳入弹框尺寸和锚点计算；问号仍没有新增点击态。
- 英文缓存说明压缩成短标题和两条单行句子。重置卡每行使用紧凑的 `#编号 · Expires 日期` 格式；两条实际日期在截图和 AX 树中均完整单行显示。
- Token 看板英文指标标签改为 `TOTAL / AVG / DAY / PEAK / PLATFORM / MODEL / CACHE HIT`，缩小水平内边距并限制标签单行。实际六格截图中标签与数值均完整，没有拥挤或换行。

### 验证

- 全量回归日志 `/tmp/qmt-help-v5-tests.log`：164 项 Swift Testing、22 项 XCTest 通过；20,000 桶分组对照一致，单次 debug 样本约 0.014 秒。
- SDD 文档验证、`git diff --check`、中英文资源键一致性均通过（各 367 个键）。候选 app 构建完成并通过签名验证。
- 候选浅色中文实机界面检查：缓存弹框标题、说明与部分数据提示完整，句子单行；重置卡日期行单行。候选深色英文实机检查：浅/深主题弹框均可读且有轻阴影，Token 六指标单行显示。检查后候选保持在 Token 看板问号说明。
- 安装后核对 `/Applications/QuotaMonitor.app` 的实际进程、二进制哈希与签名通过；用户视觉审美最终确认仍待用户查看。VoiceOver 与精确最小窗行为仍未验收。

### 本轮安装与回滚

候选 `/tmp/qmt-help-review-v5-20261109/QuotaMonitor.app` 签名验证通过后，已替换 `/Applications/QuotaMonitor.app`。安装版签名复验通过，运行进程 PID 49405 从该路径启动；候选与安装二进制 SHA-256 均为 `4a70629aff8a2b64257cf8f7fa0ae49c8d7878774a5170e082f03df756ba1b42`。旧版备份为 `.artifacts/help-shadow-install-20261109/QuotaMonitor.before.app`，另保留于 `/Applications/.QuotaMonitor.help-shadow-previous-20261109.app`。安装记录位于 `.artifacts/help-shadow-install-20261109/installation.json`。不提交、不推送。若需要回滚，将 QuotaMonitor 退出后，用本轮备份替换 `/Applications/QuotaMonitor.app` 并重开应用。

## 2026-11-09 第三次视觉审稿：浅灰细描边

- 在 `HelpBubbleShape` 同一连续轮廓上增加 0.7 pt 描边，浅色使用 `#E7E7E9`，深色使用低对比 `#38393E`；既有软阴影、箭头、尺寸留白和无点击态均保留。
- 全量回归：164 项 Swift Testing + 22 项 XCTest 通过。SDD、`git diff --check` 通过。候选签名与实际浅色中文、深色英文描边均检查；箭头和正文轮廓连续，未见接缝。
- 候选 `/tmp/qmt-help-review-v6-20261109/QuotaMonitor.app` 已替换安装。安装签名验证通过，当前 PID 53320 从 `/Applications/QuotaMonitor.app` 启动；候选和安装二进制 SHA-256 为 `e187973a453a2b374d012c35f742eec8248dc2d6247c3b3987a689e66a903b59`。
- 本轮旧版回滚包：`.artifacts/help-border-install-20261109/QuotaMonitor.before.app`；额外保留 `/Applications/.QuotaMonitor.help-border-previous-20261109.app`。安装信息见 `.artifacts/help-border-install-20261109/installation.json`。用户最终视觉确认待查看；未提交或推送。

## 概览页 Codex / Claude 卡片高度修正（2026-11-09）

- 原因：Codex 辅助行包含 18 pt 问号按钮，Claude 辅助行仅有文字，卡片依照内容高度自然撑开，导致 Claude 卡片比 Codex 矮。
- 在两张卡共用的辅助行设置 18 pt 最小高度，使两侧标题区和卡片外框等高；保留原文字、图标、帮助按钮及数据布局。
- 候选 build 和签名通过，真实概览截图确认 Codex / Claude 卡片顶部、底部对齐；SDD 和 `git diff --check` 通过。本次为单行布局修改，未运行自动化测试。
- 已按当前授权替换安装版并复查真实窗口。签名复验通过，安装版进程 PID 56119；安装二进制 SHA-256 `547059eff23ffba166d44873ba1b45416ef0494014050ff959ea8ce0e217cbb9`，候选与安装信息见 `.artifacts/overview-card-align-install-20261109/installation.json`。
- 旧版回滚包为 `.artifacts/overview-card-align-install-20261109/QuotaMonitor.before.app`，另保留 `/Applications/.QuotaMonitor.overview-card-align-previous-20261109.app`。

## 本次代码提交与推送记录

- 本次代码与文档变更对比最近已推送的 `9e46d82`；提交前确认本地 `main` 与 `origin/main` 指向同一基线。
- 本次提交覆盖 QMT-010 缓存统计与界面、QMV-011 弹框交互和审稿修订、三项页面扫描修复及概览卡片高度对齐。提交和推送完成后在此补记提交号与远端状态。

## 2026-11-09 第四次视觉审稿：弹框圆角

- 将帮助说明弹框、Token 图表 hover 数据标签、缓存排行 hover 数据标签统一为 `PanelTheme.tooltipCornerRadius = 20 pt` 的连续圆角；帮助弹框的边框、阴影、箭头和无问号点击态保持不变。
- 候选构建和签名验证通过。实际安装版概览页问号弹框已打开核对，圆角增大后更接近图表数据标签；候选图表 tooltip 也已显示核对。`./script/verify_sdd_docs.sh` 与 `git diff --check` 本轮末尾复验。此次为局部视觉 token 修改，未运行自动化测试。
- 已替换 `/Applications/QuotaMonitor.app`。安装版 PID 58275 从该路径运行；安装二进制 SHA-256：`d3786c6ae458975144c35fdeeb3f6579c89804b049cf6d61afba2fadb9ef2227`；签名复验通过。
- 回滚包：`.artifacts/help-radius-install-20261109/QuotaMonitor.before.app`；旧版另保留于 `/Applications/.QuotaMonitor.help-radius-previous-20261109.app`；安装记录：`.artifacts/help-radius-install-20261109/installation.json`。该记录编写时尚未提交或推送；后续提交 / 推送状态见本节末尾。

## 与最近一次推送基线的差异（`9e46d82`）

- 新增输入缓存命中统计：保留来源字段证据，核实 Codex、Claude Code、WorkBuddy、Claude Desktop cc-switch 与 DeepSeek Harness v4 的缓存语义；加权计算命中率、覆盖和异常原因，不改变其他来源原 Token 口径。
- 新增概览内联命中率、Token 六指标与排行 hover 说明，并补充双语文案、缓存证据模型、来源展示状态及相应测试 / Spec。
- 修复扫描发现的三项问题：排行辅助摘要补回 Token 与占比；将缓存周期汇总复用并把 hover 状态局限在排行组件；设置页区分未提供能力、无记录、扫描和故障的图标与颜色。
- 修复概览 Codex / Claude 卡片高度差；统一三类 tooltip 为 20 pt 连续圆角，并保留问号弹框浅灰描边、轻阴影与无点击态。
- 比较范围为本地 `main` 相对 `origin/main` 的全部本次变更；检查时两者均为 `9e46d82`。文件清单与自动化状态以对应变更和本验收记录为准。未纳入安装包、缓存数据、凭据或构建临时目录。

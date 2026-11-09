# 输入缓存命中展示任务与证据

> Spec：`QMT-010`；状态：Accepted / 已安装，部分验收待完成。用户已确认第二版图片并授权改代码。

| 任务 | 需求 ID | 状态 | 证据 |
| --- | --- | --- | --- |
| 建立需求、计划、设计及追踪基线 | CACHE-001～CACHE-008 | Done | 2026-11-04：第二轮比较行、六指标、原条分段、问号说明已同步到文档；SDD、9份Markdown链接/需求ID/元数据/空白检查通过；只代表文档任务完成 |
| 来源字段 / 缺省规则与最小脱敏样例核验 | CACHE-001 | Done | Codex、Claude Code、WorkBuddy、Harness、Claude Desktop 本机只读扫描通过；见 acceptance |
| 贡献证据、原数值保护及缓存迁移 | CACHE-001、CACHE-008 | Partial | 旧语义版本拒绝 / 重扫及 Codex 失败恢复测试通过；全来源物理迁移仍待验 |
| 统一缓存聚合、覆盖及来源状态 | CACHE-002、CACHE-003、CACHE-006 | Done | 加权、覆盖、来源新鲜过滤与排除原因分类实现；全量逻辑测试通过 |
| 概览比较行、顶部六指标及说明弹框 | CACHE-004、CACHE-005 | Partial | UI 已接入并安装；本轮 CUA 无法打开主面板，真实界面验收待完成 |
| 平台 / 模型排行 hover 说明 | CACHE-006 | Partial | tooltip 与相邻行 handoff 已实现；纯鼠标连续 hover 实际验收待完成 |
| 双语、键盘、VoiceOver 与主题适配 | CACHE-007 | Partial | 双语资源与等宽 tooltip 字体已接入；VoiceOver、深色及小窗待验 |
| 逻辑 / 来源 / 回归 / 迁移自动化检查 | CACHE-001～CACHE-008 | Partial | 全量 160 项通过；全来源物理迁移仍待验 |
| 来源真实只读扫描 | CACHE-001、CACHE-003、CACHE-008 | Done | 五个已接入来源完成本机只读扫描；Kimi Desktop 尚未接入 |
| 安装与主面板视觉验收 | CACHE-004～CACHE-007 | Partial | 构建 / 签名 / 安装启动通过；主面板和鼠标 hover、用户视觉验收 Pending |


图片审稿 v2 已通过内置 image_gen 生成并保存到项目 designs/cache-hit-insights/review-v2；含概览、看板与问号弹框。属于视觉意图示意，用户已确认方向，不能替代真实应用或条段几何验收。

价格阶段：deferred，尚未建立独立实施任务；完成以上任务不自动启动价格工作。

## 2026-11-08 更新

- 排除原因分类、Codex 缓存重扫与失败恢复测试、安装版主面板及键盘交互检查已完成。
- 安装版已启动并读取 Codex / Claude Code / WorkBuddy 的缓存数据。
- 菜单栏日志检查未通过；VoiceOver、真实最小窗口和用户最终视觉验收待验证。各项详细证据与回滚位置见 acceptance.md。

### 交互审稿修订

CACHE-004 / 005：简短定义与必要状态已实现。CACHE-006 / 007：排行改为 hover / focus 小浮层、移除蓝框和点击弹框；沿用原用量与缓存分母。证据见 acceptance.md 的“问号与排行交互精简”。

### 第二次审稿

CACHE-004 / 005：主面板内受限问号说明已完成；CACHE-006 / 007：移除缓存色段与右侧图例，排行仅 hover，恢复原色，其他行弱化到 0.42，浮层只含缓存率及颜色 / 名称 / 命中量。主面板与下拉原生焦点环统一抑制。构建及安装版已核对，纯鼠标联动待用户实际确认。

### 来源语义与 hover 再修订

- CACHE-001：Claude Desktop 按 cc-switch 的 `input_token_semantics` 接入；Harness v4 依据 uncached/read/write 三个分离输入桶接入。
- CACHE-002/003：两个来源加入新鲜来源集合，缓存读写不重复计入总 Token。
- CACHE-006/007：统一缓存浮层字体，内容更新为缓存命中率及“命中/输入量”；增加 80 ms 相邻行 hover 连续交接。
- CACHE-008：Additional Local Token 缓存版本 3 升到 4，旧语义数据重扫；自动化、实机和视觉状态见下方最终复验记录。

### 最终复验（2026-11-08）

- 全量 `swift test`：160 项 Swift Testing 通过；专用本机只读扫描：Codex 689/679 桶、Claude Code 7/7、WorkBuddy 19/19、DeepSeek Harness 5/5、Claude Desktop 4/4 桶/合格证据。
- 字体与 tooltip 内容、相邻条目的 80 ms hover 交接已实现，并由渲染与逻辑测试覆盖。安装包已重建、签名验证并替换；构建与安装二进制 SHA-256 相同。
- CUA 启动后只能看到空 Settings 窗口，无法从可访问界面打开状态栏主面板；自动化工具也不能发送纯 mouse-move。因此本轮未完成实际主面板截图及纯鼠标连续 hover 验收。安装已运行，最终视觉与鼠标验收仍 Pending。

### 2026-11-09 后续安装与视觉修订

- 已复查安装版概览、缓存说明弹框和概览 Codex / Claude 卡片；两卡高度已对齐，弹框圆角为共享 20 pt。
- 安装签名、进程路径与 SHA-256 已复核。纯鼠标连续 hover、VoiceOver、真实最小窗口和最终审美确认仍待验；局部视觉修改未重跑自动化测试。

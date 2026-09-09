# QuotaMonitor · Steep 视觉升级执行计划 v1.0

> 依据：`designs/codexquota-redesign/steep-design-system/DESIGN.md`（配套 tokens.json / variables.css / theme.css）
> 原则：**只动视觉层，不动功能、布局、数据结构与交互逻辑**。每阶段独立提交、可回退。
> **用户已确认范围（2026-09-09）**：产品 icon、Codex / Claude 的 icon 均不改；字体体系不改（规范 DESIGN §5 的字体部分仅作长期方向参考，本次不落地）。

---

## 0. 目标与边界

**目标**：把现有界面从"系统风格"升级为 Steep —— 白纸画布 + 雾灰静面卡片 + 单点桃色 + 24px 圆角 + 三态状态色 + 衬线标题，深浅模式各一套。

**边界（不改）**：
- 不修改任何 Store / Service / Model / 业务逻辑
- 不改 SwiftUI 视图结构与布局参数（padding/间距/坐标系）
- 不改品牌资产：`BrandIcons.swift`（产品 / Codex / Claude 品牌图标）、`MenuBarQuotaGlyph.swift`（菜单栏字形）——**用户已确认不动**
- **不改任何字体**：全部 `.font(...)` 调用保持原样
- 不改数据源与示例口径

**现状关键结论（已勘察）**：
- 全项目**没有硬编码颜色**，颜色全部经 `PanelTheme` 语义色板分发（MainPanelView 引用 143 处、DropdownViews 27 处）→ **改一个文件即可拿到 80% 的视觉效果**
- 仅 1 处系统色（MainPanelView.swift:1852 `.fill(.white)`，标题栏图标，可保留或微调）
- 图表（趋势/分时/热力图/排行）全部内置于 MainPanelView.swift

---

## 1. 改动范围总览

| 文件 | 行数 | 角色 | 改动等级 | 说明 |
|---|---|---|---|---|
| `Views/PanelTheme.swift` | 98 | 语义色板源头 | **重写（核心）** | 按迁移表替换全部色值，API 形态不变 |
| `Views/MainPanelView.swift` | 2472 | 主面板（143 处引用） | 中 | 圆角/状态/图表参数替换，无逻辑改动 |
| `Views/DropdownViews.swift` | 488 | 下拉框（27 处引用） | 中 | 浮卡化、状态与排行样式 |
| `Views/MenuBarSlotsView.swift` | 81 | 菜单栏槽位 | 不改 | 字体不调整 |
| `App/MainPanelController.swift` | 185 | 窗口底色 | 低 | 已走 PanelTheme.background，随阶段 1 自动生效 |
| `Views/BrandIcons.swift` | 196 | 产品/Codex/Claude 图标 | 不改 | 用户已确认 |
| `Views/MenuBarQuotaGlyph.swift` | 108 | 状态栏字形 | 不改 | 用户已确认 |
| `App/QuotaMonitorApp.swift` | 409 | 面板透明 | 不改 | |

**改动量估算**：PanelTheme ~70 行重写；MainPanelView 30–60 处；DropdownViews 10–20 处。全部为视觉参数替换，无逻辑分支变化。

---

## 2. 分阶段执行

### 阶段 0 · 备份与基线
- git 提交当前状态（或拷贝 PanelTheme / MainPanelView / DropdownViews 至 `_backup/`）
- `swift build` 通过；截图 3 张作 before（主面板概览、Token 看板、下拉框）

### 阶段 1 · 语义色板重写（PanelTheme.swift）
**程度**：100% 重写色值；保留 `dynamic(light, dark)` API，调用方零改动。

| 现有 token | → | 新语义 token | 浅色 / 深色 |
|---|---|---|---|
| `background` | → | `bg` | `#ffffff` / `#111215` |
| `sidebar` | → | `fog` | `#fafafb` / `#131417` |
| `surface` | → 分流 | `cardStatic`(mist) / `cardFloat`(paper) | `#f2f2f3`/`#1b1c20`、`#ffffff`/`#17181c` |
| `surface2` | → | `track`（轨道/内嵌槽） | `rgba(23,25,28,.08)` / `rgba(255,255,255,.07)` |
| `surface3` | 删除 | — | — |
| `border` | → | `hairline` | `#ececec` / `rgba(255,255,255,.08)` |
| `borderStrong` | 删除 | — | — |
| `separator` | → | `hairlineSoft` | `rgba(23,25,28,.06)` / `rgba(255,255,255,.055)` |
| `text` | → | `ink` | `#17191c` / `#cfcbc2` |
| `text2` | → | `slate` | `#777b86` / `#a29f98` |
| `text3` | → | `ash` | `#979799` / `#7c7a75` |
| `ok / warn / danger` | → 三态 | `stNormal`(slate) / `stLow`(peach+sienna) / `stCrit`(ink+bg) | 见 DESIGN §7 |
| `codexSoft` 等 Soft 底 | 删除 | — | 平台色只保留主色 |
| `categoryPalette` | → | c1–c5 | `#17191c`/`#d8d4ca`、`#5d2a1a`/`#b38668`、`#777b86`/`#8d8b92`、`#a3a6af`/`#5c5e65`、`#c9b9ae`/`#7e6a58` |
| 新增 | — | 热力图 h0–h4 | DESIGN §2.4 |
| 新增 | — | `peach` / `sienna` | `#fbe1d1`/`#d5ae93`、`#5d2a1a` |
| 平台色 codex/claude 等 | 保留 | 深色档沿用现值 | 徽标/图例小面积 |

**验证**：`swift build`；截图核对主面板/下拉框已呈现"白纸画布 + 雾灰静面"基调。
**风险**：低（纯色值替换，语义名保留）；若某视图观感异常，多半是该处误用了已删除 token，逐处修正即可。

### 阶段 2 · 卡片与圆角（MainPanelView + DropdownViews）
**程度**：结构性样式参数调整，布局不变。
- 卡片容器圆角 12→**24px**；输入/小卡 16px；按钮 9999px 胶囊
- 删除卡片描边（border 色 stroke）→ 靠 mist 与 bg 色差分层
- 投影只保留：下拉框、模态、浮动图表卡（hairline + artifact 投影）；内容卡全部去 shadow
- 卡片内分隔统一用 `hairline`，列表行间 `hairlineSoft`

**验证**：截图核对卡片层级与投影范围。
**风险**：中（需逐容器核对，机械性工作量大）。

### 阶段 3 · 状态色与平台徽标（MainPanelView + DropdownViews）
**程度**：状态组件替换。
- 正常 → 幽灵灰文字（slate，无底色）
- 偏低/注意 → 桃底棕字（peach + sienna）
- 危急/错误 → 墨底反白（ink + bg）
- 平台徽标：彩色柔底 → mist 圆底 + 平台色字/圆点；Claude 品牌橙 `#D97757` 深浅不变

**验证**：截图核对三态与徽标。
**风险**：低。

### 阶段 4 · 图表与热力图（MainPanelView）
**程度**：配色替换，绘制逻辑不动。
- TokenChart 分类色 → c1–c5；峰值/重点 → c2 笔势
- 热力图 → h0–h4 五档；网格线 → hairline；坐标轴文字 → ash
- 图例/坐标抽取值全部改为新语义色

**验证**：Token 看板页截图（趋势图 + 热力图）。
**风险**：低。

### 阶段 5 · 收尾验证与交付
- `swift build` 无新增 warning；测试套件 `swift test` 通过
- 三形态（状态栏/下拉框/主面板）× 两主题（浅/深）截图，与 before 对比
- 输出变更说明（改了什么、未改什么、可回退点）

---

## 3. 验收标准（对照规范）

- [ ] 97% 无彩：全界面桃色出现 ≤1 处/页
- [ ] 卡片一律 24px 圆角、无边框；按钮胶囊
- [ ] 投影只出现在浮动层（下拉框/模态/浮动图表卡）
- [ ] 状态三态：正常=幽灵灰、偏低=桃底棕字、危急=墨底白字
- [ ] 深色模式整体压暗（参考亮度指标：均值 ~0.11）
- [ ] 平台彩色只在小圆点/字色，无彩色柔底卡
- [ ] 深浅模式切换（系统外观跟随）无跳变
- [ ] 字体调用零改动（diff 中无 `.font` 变更）
- [ ] 品牌图标（产品 / Codex / Claude / 菜单栏字形）零改动

## 4. 风险与回退

- 每阶段独立 git commit，任一阶段可单独回退
- 阶段 1 完成后即达到"观感大改"的效果；阶段 2/3/4 为机械增强；字体与品牌图标不在本次范围，风险可控
- 若某个删除的 token（surface3/borderStrong/Soft 底）仍有引用，编译期即暴露，逐处替换为对应新语义即可

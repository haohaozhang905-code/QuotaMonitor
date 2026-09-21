---
id: QMV-001-PLAN
spec: QMV-001
title: 导航与下拉框玻璃材质技术计划
status: implemented
verification: pending
provenance: prospective
---

# 导航与下拉框透明模糊技术计划

## 方案

- 用 `NSVisualEffectView` 封装系统材质；侧栏用 `.sidebar` 与 `.behindWindow`。右侧顶部横条使用 `PanelTheme.background` 实色，并通过专用 `NSView` 将鼠标按下事件交给 `NSWindow.performDrag(with:)`，只恢复顶部拖拽而不扩大到正文。
- 2026-09-20 修订：`GlassSurface` 只承载下拉框。主面板侧栏和顶部导航条继续使用 `PanelVisualEffect`，窗口允许透明以便导航区域从桌面取样；右侧内容列重新铺实色画布。`PanelVisualEffect` 只在属性实际变化时更新，并让侧栏退出页面切换动画事务，避免切换 Tab 时闪烁。
- 2026-09-21 修订：下拉框增加独立的高对比文字 token，品牌图标保持原彩色；移除 `paper` 色调覆盖和额外加粗边框，由系统 `popover` 材质直接完成背景取样与模糊。侧栏移除固定主题色覆盖并使用 `.sidebar + .behindWindow`；深色侧栏前景统一为纯白。右侧顶部横条恢复正文实色并加入专用窗口拖拽视图。
- 数据卡、加载占位、设置分组卡、图表 tooltip 与提醒卡恢复原实色表面。侧栏选中项和分段控件恢复实色胶囊；设置开关恢复系统 `.switch` 样式。Credits 弹层维持系统原生样式。
- 下拉框和侧栏响应“减少透明度”回退实色。
- 不增加独立的模糊半径、动画或自定义着色器。设计边界遵循 [`docs/DESIGN_SYSTEM.md`](../../docs/DESIGN_SYSTEM.md)。

## 映射与验证

| 需求 | 代码 | 验证 |
| --- | --- | --- |
| GLASS-001 | `DropdownViews.swift`、`PanelTheme.swift`（GlassSurface） | 语法检查；浅深色与复杂桌面实测 |
| GLASS-002 | `MainPanelView.swift`、`MainPanelController.swift` | 语法检查；滚动、拖动和窗口切换实测 |
| GLASS-003 | `MainPanelView.swift` | 语法检查；选中项与减少透明度实测 |
| GLASS-004 | `TokenChartViews.swift`、`SettingsPageView.swift` | 语法检查；原实色控件与辅助功能实测 |
| GLASS-005 | `MainPanelView.swift`、`TokenPageView.swift`、`SettingsPageView.swift`、`ReminderToastView.swift`、`TokenChartViews.swift` | 语法检查；原实色画布、卡片和浮层实测 |

无数据迁移。若恢复全玻璃实验版本，可依据本规范的 2026-09-19 历史版本逐处恢复材质。主窗口保持透明以支持侧栏取样，右侧画布负责遮盖桌面。本机 macOS 27 beta 的 Command Line Tools 曾缺失 `SwiftUIMacros` 插件；构建状态以本次实际检查为准。安装或替换当前应用不属于本次构建验证；真实应用验收在单独运行构建后记录。

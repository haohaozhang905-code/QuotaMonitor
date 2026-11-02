---
id: QMV-007-PLAN
spec: QMV-007
title: 状态栏交互计划
status: implemented
provenance: prospective
---

# 实施计划

按用户后续确认，使用与 Status Trio v1.8.0 相同的 NSPopover、transient 行为和原生状态栏按钮；保留现有 SwiftUI 下拉内容，允许系统箭头和外框。减少动态效果时关闭系统动画；不修改状态项身份。真实观感和重复点击仍待验证。

用户确认交互正常后反馈旧白边遮挡；移除 `DropdownPopoverView` 自带背景、裁切和描边，由系统 NSPopover 负责外观，避免旧表面和系统表面叠加。

执行文档检查、构建、测试及状态项保护检查；真实运行需检查点击、点击外部、快速点击、主面板跳转、动态数据更新、浅深色、减少动态效果、屏幕边缘与全屏。安装与验收按用户后续授权执行。参考 [设计规范](../../docs/DESIGN_SYSTEM.md) 和 [架构边界](../../docs/ARCHITECTURE.md)。无数据迁移；可恢复安装前备份。

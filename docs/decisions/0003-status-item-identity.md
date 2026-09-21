---
id: ADR-0003
title: 状态栏身份集中配置并禁止 autosaveName
status: accepted
date: 2026-09-13
provenance: reconstructed
---

# ADR-0003：状态栏身份集中配置并禁止 autosaveName

## 背景

macOS Control Center 可能持久化状态栏项目的 blocked 状态，使进程正常运行时入口仍不可见。应用名称、Bundle ID 和构建脚本分散也会让安装、通知权限和登录项被系统识别为不同应用。

## 决策

- 禁止为 `NSStatusItem` 设置 `autosaveName`；
- App 名称、可执行文件、版本与 Bundle ID 集中从 `script/app_config.sh` 读取；
- 状态栏或应用身份改动必须作为独立任务和 Spec；
- 构建检查之后仍需验证 Control Center 状态，并在桌面菜单栏看到真实入口；
- 修改 Bundle ID 只作为明确评估后的迁移，不作为普通故障绕行方案。

## 结果

构建脚本受到更强约束，降低安装身份漂移和状态栏永久消失的概率。自动检查无法证明 UI 已出现，仍保留真实验收步骤。

## 证据

- `CONTRIBUTING.md`
- `script/app_config.sh`
- `script/security_check.sh`
- `script/verify_menu_bar_status.sh`

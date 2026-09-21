---
id: ADR-0002
title: 提醒状态使用规则 ID 与 V3 账本
status: superseded
superseded_by: ADR-0004
date: 2026-09-13
provenance: reconstructed
---

# ADR-0002：提醒状态使用规则 ID 与 V3 账本

> 该决策记录 V3 引入规则 ID 账本时的历史语义，现行持久化与迁移由 [ADR-0004](0004-reminder-ledger-v5.md) 替代。

## 背景

额度分档、窗口重置、机会到期、余额恢复线和 Token 里程碑拥有不同去重语义。继续为每种事件增加独立字段，会使规则、Coordinator、文案和迁移持续分叉。

## 决策

- 每条提醒规则拥有稳定规则 ID；
- `ReminderRuleCatalog` 集中声明来源、条件、去重、顺序、目标和文案；
- V3 账本按规则 ID 保存 occurrence、激活状态、周期和观测基线；
- 迁移顺序保持 V1→V2→V3，并保留旧键供兼容和回滚读取；
- 新增普通阈值优先登记目录，新条件语义才扩展执行器。

## 结果

规则新增与投递逻辑解耦，持久状态可以按规则迁移和测试。稳定 ID 成为长期兼容契约，不能随展示文案改名。

## 证据

- `specs/001-reminder-v1.1/spec.md`
- `Sources/QuotaMonitor/Models/ReminderModels.swift`
- `Tests/QuotaMonitorTests/ReminderRuleTests.swift`

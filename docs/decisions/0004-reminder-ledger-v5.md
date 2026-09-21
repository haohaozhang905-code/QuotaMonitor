---
id: ADR-0004
title: V5 账本按确认的额度补充周期去重
status: accepted
date: 2026-09-19
provenance: reconstructed
supersedes: ADR-0002
---

# ADR-0004：V5 账本按确认的额度补充周期去重

## 背景

V3/V4 账本已经按规则 ID 保存状态，但额度档位仍可能依赖服务端持续变化的重置时间。滚动时间会让同一轮 30% 或 5% 额度被识别成新的 occurrence；睡眠、锁屏和通知授权等待也可能让候选事件在没有真正展示时被错误消费。

## 决策

- V5 为 5 小时额度和周额度分别保存补充周期编号、已提醒档位、上一条显示百分比和原始重置时间；
- 只有可信的额度恢复或补充证据才能开始新周期，单纯的重置时间后移不重新启用额度提醒；
- 观察到 5% 档时同时将 30% 档视为已处理，避免冷启动连续弹出两条提醒；
- 规则评估先产生候选账本，投递层返回实际接受的事件后再提交相应去重状态；
- 用户不可交互时不评估或积压提醒，恢复后只使用最新的新鲜数据；
- V1～V4 按顺序迁入 V5 并保留旧键，防止升级后重复提醒，也为回滚提供读取基础。

## 结果

额度提醒不再随滚动重置时间重复，环境抑制和投递竞态不会提前消耗提醒。旧版本无法理解 V5 的补充周期，跨版本反复回滚仍可能重新出现旧的误报行为。

## 证据

- `specs/001-reminder-v1.1/spec.md`
- `specs/001-reminder-v1.1/plan.md`
- `Sources/QuotaMonitor/Models/ReminderModels.swift`
- `Sources/QuotaMonitor/Services/ReminderCoordinator.swift`
- `Tests/QuotaMonitorTests/ReminderRuleTests.swift`

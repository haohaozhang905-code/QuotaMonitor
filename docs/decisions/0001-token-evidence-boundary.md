---
id: ADR-0001
title: Token 统计只使用可验证字段
status: accepted
date: 2026-09-13
provenance: reconstructed
---

# ADR-0001：Token 统计只使用可验证字段

## 背景

不同 AI 工具的本地文件可能同时包含上下文窗口、调用级 usage、缓存 Token、积分、费用或不完整汇总。字段名称相近，不代表业务语义相同。

## 决策

- 只有能够确认单位、时间、模型和去重边界的字段才能进入精确 Token 汇总；
- 上下文窗口、文本长度、Credits 和无法解释的汇总值不能转换成精确输入/输出 Token；
- 来源专用字段保留在对应 client 中解析，公共扫描层只处理缓存、文件边界和目录等共性；
- 缺失和无法解析的数据保持未知，不填充为零；
- 新来源需要脱敏样例、字段说明和边界测试。

## 结果

统计覆盖速度可能降低，但数字能够解释，并减少跨工具错误比较。通用适配器只能声明其真实覆盖能力。

## 证据

- `docs/DATA_SOURCES.md`
- `Sources/QuotaMonitor/Services/LocalTokenScanSupport.swift`
- `Sources/QuotaMonitor/Services/WorkBuddyTraceClient.swift`
- `Tests/QuotaMonitorTests/LocalTokenSourceTests.swift`

---
id: QMT-004
title: WorkBuddy JSONL Trace 兼容
status: implemented
verification: automated-and-local-source-scan-passed-install-pending
provenance: prospective
---

# WorkBuddy JSONL Trace 兼容产品规范

## 用户问题与目标

WorkBuddy 更新后开始把 Trace 主要写成 `.jsonl`。QuotaMonitor 仍只发现 `.json`，导致 2026-10-13 晚之后的本地 Token 使用没有进入看板。本次恢复最近用量，同时保持旧格式、明确 usage 字段和现有日期/模型口径。

## 需求

- **WBT-001**：`~/.workbuddy/traces` 中的 `trace_*.json` 与 `trace_*.jsonl` 都参与统计，兼容旧 Trace 汇总和 generation usage。
- **WBT-002**：JSONL 继续只读取 generation `toolOutput` 中明确的输入、输出、缓存与推理 Token，不根据文本长度、上下文占用或其他字段推估。
- **WBT-003**：同一 `traceId` 同时存在 JSON 与 JSONL 时只统计一次，优先追加写入的 JSONL；缓存升级后完整重建一次，避免旧缓存遮蔽新增文件。
- **WBT-004**：源 Trace 保持只读；追加扫描、缓存重载和重复扫描不重复累计，缺失或无法确认的用量不补算。

## 范围与非目标

仅修改 WorkBuddy 本地 Trace 发现、格式切换去重、缓存版本和相关文档测试。不修改 Codex、Claude、提醒、状态栏、应用身份或安装流程；不读取 WorkBuddy 对话内容用于估算，不补回本机已经删除或没有明确 usage 的请求。本轮按用户要求只改代码并验证，不替换安装应用。

## 验收

自动化覆盖旧 JSON、新 JSONL、同 `traceId` 双格式去重、generation usage 字段及现有追加/边界保护。本机验收使用生产解析器直接只读扫描真实 Trace，确认最近日期恢复、重复扫描稳定、全部源文件内容摘要/大小/修改时间不变。安装版 Token 看板留待后续明确授权后验收。

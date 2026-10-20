---
id: QMT-004-PLAN
spec: QMT-004
title: WorkBuddy JSONL Trace 兼容技术计划
status: implemented
verification: automated-and-local-source-scan-passed-install-pending
provenance: prospective
---

# 技术执行计划

## 实现

1. 保留 `WorkBuddyTraceClient` 的头部 Trace 汇总与 generation 定向分块解析，只把文件发现范围扩展到 `.json` 和 `.jsonl`。
2. 缓存条目记录 `traceId` 与源格式；相同 `traceId` 选择 JSONL，格式相同时选择更完整的较大文件。无法取得标识的旧 Trace 继续按独立文件处理，不猜测关联关系。
3. 缓存 envelope 从版本 2 升到版本 3，使升级后的第一次刷新从源 Trace 完整重建；之后继续复用文件指纹和追加扫描。
4. 增加脱敏 JSONL fixture、双格式去重测试和显式启用的本机只读集成测试；同步数据源与追踪文档。

## 风险、回滚与交付

JSONL 内部 generation usage 仍可能随 WorkBuddy 后续版本变化；解析不到明确字段时保持缺失，不做估算。回滚代码会继续忽略 `.jsonl`，源 Trace 无迁移、无需回滚。缓存可安全重建，回滚前可删除或留给旧版忽略。本轮不组装、不替换安装应用。

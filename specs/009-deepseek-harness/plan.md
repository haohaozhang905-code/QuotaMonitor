---
id: QMT-009-PLAN
spec: QMT-009
title: DeepSeek Harness 采集计划
status: implemented
provenance: prospective
---

# 实施与验证

复用 AdditionalLocalTokenClient 缓存和内置 Zstandard 流式解码器，增加独立格式和平台。每个会话目录选择最高代日志；解析 v4 明确消息用量及事件时间。压缩文件变动时全量重算，不对压缩字节使用追加游标。对继承历史或未知版本跳过。测试重复消息、版本、缺字段、追加、损坏缓存恢复，使用真实源只读扫描核对。同步来源文档和追踪矩阵。回滚代码即可停止采集；源文件不变，缓存可重新生成。

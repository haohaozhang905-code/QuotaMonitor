---
id: QMT-008-PLAN
spec: QMT-008
title: 模型排行过滤计划
status: implemented
provenance: prospective
---

# 实施计划

在展示层按模型和时间窗口汇总后过滤非正数，再计算占比和 Top N；仅模型排行启用过滤。保留来源数据、缓存和聚合桶，不涉及迁移。通过展示快照测试、项目文档检查及 Swift 测试验证；安装版菜单和看板需另行验收。回滚可撤销本次展示层与文档改动，无需恢复数据。

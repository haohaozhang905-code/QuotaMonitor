# Codex 同一会话多日志片段用量合并任务与证据

> Spec：`QMT-012`<br>
> 状态：已实现；安装启动已核验；Token 看板待用户验收

| 任务 | 需求 ID | 状态 | 证据 |
| --- | --- | --- | --- |
| 复现同 session ID 多 rollout 导致旧模型片段被丢弃 | ROLL-001 / 002 | Done | 目标会话两份本机 JSONL：较早片段 261 条 gpt-6.2-sol usage，较新片段 83 条 gpt-6-luna usage；目录发现按 session ID 去重 |
| 分析同一 session 多 rollout 的历史候选 | ROLL-001 / 003 | Partial | 598 个 JSONL / JSONL.ZST rollout 文件、567 个 session ID；25 个 ID 有多个 rollout 文件，整库已按新规则扫描。目标外另有多模型候选；历史旧口径实际漏计量与正式缓存 27 条旧修订记录的具体原因尚未逐项确定 |
| 设计事件合并、缓存迁移与失败回滚 | ROLL-002 / 003 / 004 | Done | `plan.md`；正式缓存路径确认，未修改缓存 |
| 实现会话片段分组与重叠去重 | ROLL-001 / 002 / 004 | Done | `CodexSessionTokenClient`；JSONL / ZST 同会话多片段测试 |
| 重建 revision 与缓存失败保护测试 | ROLL-003 | Done | revision 2 / cache evidence 3；旧缓存污染重算、重载、坏片段 last-good 测试 |
| 本机临时缓存历史扫描和源文件不变核验 | ROLL-003 / 004 | Done | 574 个压缩源文件；冷扫 / 重载历史桶一致，哈希、大小和 mtime 不变 |
| 更新数据源 / 追踪文档并通过 SDD | ROLL-001–004 | Done | `DATA_SOURCES.md`、`TRACEABILITY.md`、规范索引；`verify_sdd_docs.sh` 通过 |
| 针对性与全量自动化验证 | ROLL-001–004 | Done | Codex / 压缩历史回归及全量 166 项测试通过；`git diff --check` 通过 |
| 替换安装版并触发正式缓存迁移 | ROLL-003 | Done | `/Applications/QuotaMonitor.app` 已替换并启动；签名校验通过；正式 Codex 缓存已升至 v6（567 条记录，其中 540 条为新聚合 / 证据修订） |
| 验收安装版目标会话模型显示 | ROLL-001 / 002 | Pending | 应用已启动；仍需在 Token 看板确认目标日期同时显示 `gpt-6.2-sol` 与 `gpt-6-luna` |

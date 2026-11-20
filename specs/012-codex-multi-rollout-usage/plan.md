---
id: QMT-012-PLAN
spec: QMT-012
title: Codex 同一会话多日志片段用量合并技术计划
status: implemented
verification: automated-local-scan-and-installed-launch-verified
provenance: prospective
---

# Codex 同一会话多日志片段用量合并技术计划

## 1. 执行目标

将 Codex 日志识别为“会话中的多个 rollout 片段”，保留每段新增请求，并在片段和副本边界做可解释的事件去重。

## 2. 当前架构与约束

`CodexSessionTokenClient` 发现 JSONL / JSONL.ZST 文件，按文件缓存累计用量与模型桶；`discoverSessionFiles()` 将同一 `session_id` 视为一个别名组并只留一个文件，且同格式按 mtime 新者优先。模型状态由 `turn_context` / `world_state` 等事件更新，再应用到请求级 usage。fork 通过父子累计序列共同前缀处理。

Codex 缓存位于 `~/Library/Caches/com.cmsjcm.QuotaMonitor/codex-session-token-cache-evidence-v1.json`（由系统 Caches 目录解析）。旧缓存按版本和聚合 revision 判定可复用；Store 在来源扫描失败时保留 last-good Token 桶。

## 3. 目标设计

- 将精确 rollout 身份（标准 rollout 名称 / 路径别名）与逻辑 session ID 分开；session ID 用于组装片段与 fork 关系，不再用于丢弃同会话的不同 rollout。
- 同一逻辑会话按片段起始时间和行内顺序串行处理，延续模型上下文与累计 usage 基线。
- 对不同片段间重复的请求事件，在内存中用规范化的时间戳、模型上下文、`last_token_usage` 与 `total_token_usage` 字段识别；无请求级字段时用累计序列求差。该指纹不写入持久缓存，不读取或保存正文。
- 对同 rollout 普通 / 压缩、跨目录副本沿用副本选择；完整会话重算时按顺序汇总模型桶。
- 新增聚合 revision，拒绝复用旧的“每 session 只留一段”结果。成功全量重算后替换缓存；任何必要片段不可读则让来源扫描失败，由 Store 保留 last-good。
- fork 子会话的父序列由父会话所有片段按顺序组成，仍通过累计 usage 前缀判断继承边界。

## 4. 需求映射

| 需求 ID | 实现模块 | 测试 |
| --- | --- | --- |
| ROLL-001 | `CodexSessionTokenClient` 文件发现、会话分组 | 同 session ID 多 rollout、顺序不受目录枚举和 mtime 改变影响 |
| ROLL-002 | 片段串行解析、模型上下文、事件重叠识别 | 模型切换、重复前缀、同累计不同请求、无请求级字段差分 |
| ROLL-003 | 缓存 revision、last-good 流程 | V5 旧缓存强制重算、重载一致、失败不覆盖、追加后稳定 |
| ROLL-004 | 副本与 fork 去重 | 普通 / 压缩双副本、跨目录副本、父子累计前缀、损坏日志和源只读 |

## 5. 实施阶段

1. 增加脱敏 fixture 与回归测试，复现多个 rollout 共用 session ID、不同模型以及重叠边界。
2. 重构文件身份与会话分组，改为按会话合并片段并在解析期维护模型和累计状态。
3. 加入片段级缓存失效与新 revision，测试旧缓存冷重算、缓存重载和 last-good。
4. 对目标日志及当前候选历史组做临时缓存只读扫描；仅输出聚合日期、模型桶、文件数和摘要。比对源文件前后哈希、大小、mtime。
5. 更新数据来源、Spec、Plan、任务、验收、README 索引和追踪矩阵；运行 SDD 文档校验、针对性测试及全量测试。

主要实现文件：`Sources/QuotaMonitor/Services/CodexSessionTokenClient.swift`；主要测试文件：`Tests/QuotaMonitorTests/LocalTokenSourceTests.swift` 与 `Tests/QuotaMonitorTests/CompressedCodexHistoryTests.swift`；说明文件：`docs/DATA_SOURCES.md`、`docs/TRACEABILITY.md`。

## 6. 迁移与兼容

- 提升 Codex session 聚合 revision；不尝试把旧缓存桶反推为多个 rollout，因为旧缓存已经丢失被淘汰片段的边界信息。
- 先在隔离临时根目录和临时缓存验证冷扫、重载与旧 revision 重算；不得直接改写正式缓存做实验。
- 正式运行时从现存 JSONL / JSONL.ZST 只读重算。缓存写入使用现有原子保存路径；若扫描失败，保留旧缓存和 Store last-good。
- 回滚代码可继续读取现存缓存 envelope 中兼容字段；旧版会恢复“同 session ID 只留一文件”的统计行为。源日志不需回滚。回退前保留新缓存副本，避免新旧口径混用。
- 实现阶段不改 Token 快照、应用身份或安装流程；替换安装需另有明确授权。本次后续安装按用户授权单独记录于第 8 节。

## 7. 测试与验收

- 单元测试：段序、模型切换、事件重复签名、仅累计差分、相同累计值的独立请求、无时间戳回退。
- 集成测试：JSONL / ZST 多片段、压缩与普通副本、fork、缓存 revision、追加、缓存重载、损坏和取消。
- 本机只读集成扫描：隔离缓存比较冷扫 / 重载全模型桶；记录现存历史候选组影响；源日志前后哈希、大小和修改时间不变。
- 真实 UI / 安装验收：安装与进程启动已经核验；仍需确认 Token 看板是否显示目标会话两个模型，并分别测量首轮刷新及暖缓存重启耗时。

## 8. 发布与回滚

实现阶段完成源代码、文档、自动化测试和隔离本机扫描；后续经用户单独授权，于 2026-11-20 替换并启动 `/Applications/QuotaMonitor.app`。旧应用和缓存备份在 `~/Library/Application Support/QuotaMonitor Backups/QuotaMonitor-before-20261120-225114/`。未提交、未推送。回滚可恢复 `Previous-Applications-QuotaMonitor.app` 与 `Caches/`；源日志从未写入。

### 实施后运行观察（2026-11-20）

- 安装包签名验证通过，Bundle ID 为 `com.cmsjcm.QuotaMonitorStatus4`，版本 0.1.8 build 10；进程成功启动。
- 正式 Codex 缓存已从旧 envelope v5 更新为 v6。启动进程与新缓存写出相隔约 2 分 15 秒；该区间包含完整应用运行过程，不能视为精确扫描计时。
- 隔离扫描参考值为冷扫约 65 秒、缓存重载约 4.7 秒。下一次性能比较应在 v6 缓存已生成后测量同一安装版的进程启动、首轮刷新完成和 Token 页可交互时间。
- 用户尚未确认 Token 看板中目标会话的两个模型行；真实界面数据验收仍待完成。

## 9. 完成定义

ROLL-001～004 fixture 回归、SDD 文档校验、针对性和全量测试、本机临时缓存冷扫 / 重载、源日志不变检查及历史候选审查全部有记录；安装版视觉和用户验收保持单独待办。

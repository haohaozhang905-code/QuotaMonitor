# Codex 同一会话多日志片段用量合并验收记录

> Spec：`QMT-012`<br>
> 当前结论：自动化、本机隔离扫描及安装启动通过；Token 看板的目标会话模型显示待用户验收

## 自动化验收

| 场景 | 需求 ID | 预期 | 证据 | 状态 |
| --- | --- | --- | --- | --- |
| 同一 session ID 的 Sol → Luna 两个 rollout 片段 | ROLL-001 / 002 | 两模型都保留且各自请求只计一次 | `CodexSessionTokenClientTests.mergesRolloutSegmentsForOneSessionAndDeduplicatesOverlappingEvents` | Passed |
| 片段存在完全重复请求事件 | ROLL-002 | 重复事件只计一次 | 同上，覆盖交界重复请求 | Passed |
| 相同累计值但独立请求 / total-only usage | ROLL-002 | 依请求字段口径保留，不因累计值相同而删事件 | 同上，累计值不变的显式请求仍计入 | Passed |
| JSONL / JSONL.ZST 同 rollout 副本、父子 fork | ROLL-004 | 每笔实际请求最多计一次，fork 继承前缀排除 | `CompressedCodexHistoryTests`、现有 fork 回归 | Passed |
| 旧缓存重建、缓存重载和不可读源 | ROLL-003 | 新旧 revision 不混用；失败保留 last-good | 多片段污染缓存重建、重载和损坏片段回归 | Passed |
| 源日志完整性 | ROLL-004 | 扫描前后哈希、文件大小和 mtime 一致 | 本机隔离扫描核对 574 个压缩源文件 | Passed |
| SDD、针对性及全量测试 | ROLL-001–004 | 检查通过 | 全量 166 项测试；`verify_sdd_docs.sh`；`git diff --check` | Passed |

## 真实环境与视觉验收

| 环境 / 场景 | 预期 | 构建或提交 | 证据 | 状态 |
| --- | --- | --- | --- | --- |
| 隔离缓存本机冷扫 / 重载 | 今日以前全模型桶一致；压缩源文件不变 | 临时缓存，2026-11-20 | 574 个压缩文件哈希 / 大小 / mtime 不变；今日以前冷扫与重载一致。冷扫约 65 秒，重载约 4.7 秒 | Passed |
| 安装版替换、签名与进程启动 | 应用身份正确，进程可启动 | 2026-11-20 工作区构建；替换 `/Applications/QuotaMonitor.app` | Bundle ID `com.cmsjcm.QuotaMonitorStatus4`、版本 0.1.8 build 10；签名验证通过；PID 88796 在检查时运行 | Passed |
| 正式缓存迁移 | 旧缓存被新 revision 重算，源日志只读 | 安装版首次扫描，2026-11-20 | Codex 缓存从 v5 写为 v6，共 567 条记录；其中 540 条具有 aggregation revision 2 / cache evidence revision 3。目标统计页的具体模型显示仍需用户确认 | Runtime observed; visual pending |
| 安装应用 TOKEN 看板目标会话 | 同日同时显示 `gpt-6.2-sol` 与 `gpt-6-luna`，无重复累计 | 安装版 2026-11-20 | 尚未取得用户对目标日期及模型行的实际界面确认 | Pending |

## 启动与扫描耗时观察

- 隔离环境冷扫 574 个压缩历史源约 65 秒，缓存重载约 4.7 秒；该测量与安装版不是同一次受控对照。
- 安装进程于 22:51:48 启动，正式 Codex 缓存 v6 文件于 22:54:03 更新。约 2 分 15 秒是进程启动到缓存写出的观测间隔，不是独立计时器测出的纯解析耗时。
- `QuotaStore.start()` 并行启动额度与本地 Token 首轮刷新，但 Codex 来源没有单独超时；首轮刷新完成状态在 `refreshAll()` 返回后设置。缓存迁移期间的面板可用性与实际视觉等待尚未测量。
- 本次测量表明缓存迁移会带来明显一次性成本；后续常态启动耗时仍需基于已升至 v6 的缓存做同条件复测，不能用隔离环境的 4.7 秒代替安装版结论。

## 剩余风险

- 当前本机发现 25 个同 session ID 多 rollout 组。隔离扫描已解析候选历史；安装版正式缓存共有 567 条记录，其中 27 条未进入 revision 2 / evidence revision 3，原因尚未逐条审查。另有至少两个未压缩历史会话表现为模型分散在不同片段，具体旧版漏计 Token 量无法从旧界面缓存回溯。
- 删除、不可读或缺失结构化 usage 的历史日志无法恢复；云端和其他设备用量仍不在本机覆盖范围。

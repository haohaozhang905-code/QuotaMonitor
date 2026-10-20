# WorkBuddy JSONL Trace 兼容任务与证据

Spec：QMT-004。

| 任务 | 需求 | 状态 | 证据 |
| --- | --- | --- | --- |
| 核对真实格式与断点 | WBT-001、002 | Done | 本机 `.json` / `.jsonl` 文件分布、Trace 头部与 generation usage 结构只读核对 |
| 扩展发现与双格式去重 | WBT-001、003 | Done | `WorkBuddyTraceClient` 与脱敏 fixture |
| 缓存升级及回归保护 | WBT-003、004 | Done | V3 envelope、WorkBuddy 单元测试与全量测试 |
| 本机真实 Trace 隔离扫描 | WBT-001～004 | Done | 显式集成测试；重复扫描一致且源文件未变化 |
| 替换安装与运行缓存验收 | WBT-001～004 | Done | 正式应用已替换并启动；V3 缓存含 105 个条目、63 个 JSONL，最新日期为 2026-10-20 |
| Token 看板视觉验收 | WBT-001～004 | Pending | 状态栏门禁未记录初始化，尚未完成页面级视觉确认 |

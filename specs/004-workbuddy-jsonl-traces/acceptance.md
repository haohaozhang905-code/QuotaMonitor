# WorkBuddy JSONL Trace 兼容验收记录

Spec：QMT-004。日期：2026-10-20。代码、自动化、本机真实源只读扫描和替换安装后的运行缓存已通过；Token 看板视觉验收仍待完成。

## 根因证据

- 正式 WorkBuddy 缓存仅包含 42 个 `.json` 条目，最新模型桶停在 2026-10-13。
- 本机 Trace 目录另有 63 个 `.jsonl` 文件，覆盖 2026-10-13 晚至 2026-10-20；旧扫描条件全部排除。
- JSONL 仍由首行 Trace 元数据和后续 generation span 组成，明确 usage 位于 `toolOutput`，现有定向解析口径可继续复用。

## 自动化与本机验证

| 场景 | 结果 |
| --- | --- |
| 旧 JSON 汇总与 generation usage | 原有测试继续通过 |
| 新 JSONL generation usage | 脱敏多行 fixture 通过 |
| 相同 `traceId` 的 JSON / JSONL 双副本 | 只保留 JSONL，用量未相加 |
| 追加、跨读取块及 `toolInput` 假 usage | 原有保护测试继续通过 |
| 本机真实 Trace 扫描 | 105 个文件（其中 63 个 JSONL）解析成功，最新日期恢复至 2026-10-20 |
| 重复扫描与源文件保护 | 今日以前结果一致；全部源文件 SHA-256、大小和修改时间不变 |
| 替换安装后的运行缓存 | 正式应用生成 V3 缓存，105 个条目、63 个 JSONL，最新模型桶日期为 2026-10-20 |
| 全量回归 | 144 项 Swift Testing（2 项显式本机集成默认跳过）与 14 项 XCTest 通过；WorkBuddy 本机集成另显式通过 |
| Release 构建与工程门禁 | `swift build -c release`、SDD 文档检查、安全检查及差异空白检查通过 |

应用已替换并启动。`build_and_run.sh --verify` 的签名和进程检查通过，但 Control Center 未记录状态项初始化，因此状态栏门禁返回失败；真实 Token 看板视觉验收未完成。

# Codex 压缩历史日志任务与证据

Spec：QMT-003。

| 任务 | 需求 | 状态 | 证据 |
| --- | --- | --- | --- |
| 复用与依赖核对 | HIST-001 | Done | 官方 v1.5.7 解码源码、BSD LICENSE、维护与版本记录已查 |
| 内置流式解码与普通行读取复用 | HIST-001、003 | Done | `CZstd`、`JSONLReader` 与 fixture 测试 |
| 副本、fork、缓存转换及旧增量校准 | HIST-002、004 | Done | 9 项新增 fixture 与 9 项原 Codex 测试通过 |
| 全量回归与真实历史隔离扫描 | HIST-001～004 | Done | 142 项 Swift Testing、14 项 XCTest；本机集成另显式通过，全部压缩源文件完整性校验见 acceptance.md |
| 发布构建 | HIST-001 | Done | Universal Release 构建及签名校验通过 |
| 安装与 GUI 验收 | HIST-001～004 | Done | 后续用户授权替换安装；实际点击累计、重启复核及正式缓存逐日摘要与冷扫一致 |

# DeepSeek Harness 验收

日期：2026-11-03。代码已实现；安装版 Token 看板已验证，菜单栏入口验收待完成。

- 本机 DeepSeek Harness 0.2.1-rc.5 的会话 v4 包含消息级 usage；同一 usage 也出现在 stream 中。上游安装包文档说明会话保留历史 generation，并选最高版本。
- 使用生产解析器只读扫描本机会话，发现可读取的最高版本日志；独立读取计算一致，重复扫描结果一致。这是当时可识别的本地数据，不是账户账单。
- 自动化测试覆盖消息重复、流式镜像、缺失字段、旧版本、seeded 会话、追加、缓存重载以及压缩读取失败沿用缓存。
- 全量测试：Swift Testing 149 项通过（3 项本机集成默认跳过，DeepSeek 本机集成已单独启用通过）；XCTest 17 项通过。SDD 文档检查与差异空白检查通过。
- v3、seeded 会话和辅助请求暂不承诺覆盖。

## 安装版验收（2026-11-03）

- 已从当前工作区构建并安装 `/Applications/QuotaMonitor.app`，签名校验通过，应用进程运行。
- 实际 Token 看板“近7日”的平台用量中显示 DeepSeek Harness；观察到用量随源日志更新，界面四舍五入后的数值与应用缓存一致。
- 菜单栏自动检查两次均报告 Control Center 未记录该进程的状态项初始化；本次通过应用窗口检查了看板，但未完成菜单栏图标及下拉框验收。
- 替换前版本已压缩备份于用户 Library 的 `Application Support/QuotaMonitor Backups`，可解压后恢复。

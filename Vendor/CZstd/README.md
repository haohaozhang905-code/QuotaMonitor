# Zstandard 解码组件

来源：https://github.com/facebook/zstd 。于 2026-10-18 核对维护状态与发布版本。
固定版本：v1.5.7，提交 `f8745da6ff1ad1e7bab384bd1f9d742439278e99`。
许可：采用上游 BSD/GPL 双许可中的 BSD-3-Clause 选项，原文见 LICENSE。

`zstddeclib.c` 由上游脚本合并生成，仅包含解码器；生成后不作手工修改：

```
cd zstd/build/single_file_libs
python3 combine.py -r ../../lib -x legacy/zstd_legacy.h -o zstddeclib.c zstddeclib-in.c
```

`zstd.h` 和 `zstd_errors.h` 原样复制自上游 `lib/`。SwiftPM 直接编译此 C target，
运行时无需编码器、外部命令或远程服务。BSD 许可声明随应用资源包分发。

SHA-256:

- zstddeclib.c: `5eb38abe0a7eea13674b312a006df72002d4192f0f0b4d09e6f03fb927a1f3d0`
- zstd.h: `9b4bc8245565c98ccfc61c07749928b57e7c0f6fddb0530c4f6aa1971893d88b`
- zstd_errors.h: `66a8c3f71d12ea6e797e4f622f31f3f8f81c41b36f48cad4f5de7d8bfb6aac0a`

`reader.c` 与 `include/CZstd.h` 是 QuotaMonitor 自有的只读流包装，支持连接帧，
检查帧结束及文件携带的校验和，将解码窗口限制为 128 MiB。Swift 层按块读取并检查取消状态。
读取过程不落盘解压内容，也不改名或写入源日志。

接入前已核对上游实现及许可。自动化测试、本机历史扫描与安装版验收结果见
[验收记录](../../specs/003-compressed-codex-history/acceptance.md)。

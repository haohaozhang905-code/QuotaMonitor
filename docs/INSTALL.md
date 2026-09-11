# 安装与使用 QuotaMonitor

[返回 README](../README.md) · [工具支持清单](DATA_SOURCES.md) · [隐私说明](../PRIVACY.md)

## 先确认环境

- **运行系统：** macOS 14 或更高版本；当前没有 Windows / Linux 版本。
- **芯片：** 源码可在 Apple silicon 或 Intel Mac 上构建，发布构建脚本包含两种架构。具体安装包的支持情况以其发布说明为准。
- **源码构建：** 需要 Swift 6 及可用的 macOS SDK。安装支持 Swift 6 的 Xcode Command Line Tools 或 Xcode；旧版工具链即使已经安装，也可能不满足要求。
- **数据准备：** 只需准备你要查看的工具。查询 Codex 额度需在同一 macOS 用户下登录 Codex；其他工具的本地 Token 统计不依赖 Codex 订阅。
- **费用：** QuotaMonitor 使用 MIT 许可证，没有应用内订阅。工具链下载、编译需要时间和磁盘空间；协助安装的 Agent 与 AI 服务可能有各自的费用。

截至 **2026-09-07**，仓库没有 Release 安装包。当前可采用下面的 Agent 安装或手动源码安装。

## 方式一：让 Agent 帮你安装

使用具备本机终端和文件操作权限的编程 Agent，发送：

> 帮我安装这个软件：https://github.com/haohaozhang905-code/QuotaMonitor 。先阅读 README.md 和 docs/INSTALL.md，检查系统、Swift 版本和已有安装。有正式 Release 安装包就核实兼容性、来源及签名状态后安装；没有则从源码构建，使用仓库支持的本地 ad-hoc 签名方式。保留已有源码修改；若需下载工具链、系统授权或替换已有应用，请先说明影响。完成后检查应用进程和菜单栏入口，并告诉我已经检测到的数据源及下一步配置。不要输出或上传 API Key、认证文件和完整对话日志，不要关闭系统安全保护。

Agent 应按以下顺序处理：

1. 检查系统与工具链；先确认目标目录是否已存在，不覆盖已有工作目录。
2. 读取实际 Release 状态。没有可用附件时走源码路径，不把“Source code”压缩包当成应用安装包。
3. 检查构建脚本并运行适当验证；源码本地安装使用下文的 ad-hoc 签名参数。
4. 安装到 `/Applications/QuotaMonitor.app`，说明是否替换了旧应用。
5. 确认进程能启动、菜单栏入口可见，并将“安装成功”和“数据源已准备好”分别核对。没有可读日志时应如实报告，不生成用量。
6. 记录安装版本 / 提交号与源码位置，方便更新及回退。

## 方式二：手动从源码安装

### 1. 检查构建工具

在终端运行：

```bash
sw_vers -productVersion
uname -m
xcode-select -p
swift --version
```

系统需为 macOS 14+，Swift 需为 6 或更新版本。尚未安装命令行工具时运行下面的命令，按系统提示完成安装后再检查：

```bash
xcode-select --install
```

若系统提供的命令行工具不含 Swift 6，需安装兼容的 Xcode / 工具链并选中它；不要将“安装过 Command Line Tools”视为版本检查已通过。

### 2. 获取代码

先在终端进入你希望保存项目的父目录，再执行：

```bash
git clone https://github.com/haohaozhang905-code/QuotaMonitor.git
cd QuotaMonitor
```

若同名目录已经存在，请先检查其中的内容，或选择新的目录名；不要覆盖、删除已有项目来解决克隆冲突。

### 3. 检查并安装

以下命令在项目目录内执行：

```bash
swift test
./script/security_check.sh
QUOTAMONITOR_ALLOW_ADHOC=1 QUOTAMONITOR_SIGNING_IDENTITY=- ./script/build_and_run.sh --verify
```

最后一条命令会编译、组装应用、校验签名、安装到 `/Applications/QuotaMonitor.app` 并启动它。它会结束并替换正在运行的旧版 QuotaMonitor，也会清理仓库 `dist` 下的旧应用副本；不用于替换你的源代码或删除 AI 工具日志。写入“应用程序”可能需要系统或 Agent 的权限批准。

`QUOTAMONITOR_ALLOW_ADHOC=1` 和 `QUOTAMONITOR_SIGNING_IDENTITY=-` 用于本机源码构建，无需开发者证书。**ad-hoc 签名不等于 Apple 公证，也不应作为已公证的公开安装包宣传。**

构建脚本会按自身配置运行 SwiftPM；如果 Agent 环境仍限制编译缓存或应用安装目录，应按宿主提示授权对应操作，不要通过关闭 macOS 安全保护来排障。

`--verify` 会检查启动后的进程；还需自行确认菜单栏入口和实际界面。本说明不承诺固定安装时长。

## 后续有 Release 安装包时

1. 打开[本仓库 Releases](https://github.com/haohaozhang905-code/QuotaMonitor/releases)，阅读对应版本的系统、芯片及签名 / 公证说明。
2. 下载发布者实际提供的 DMG；GitHub 自动生成的源码压缩包不含可直接运行的安装程序。
3. 若提供 SHA-256 校验值，下载后比对。校验值用于确认文件一致性，签名和公证用于不同的信任检查。
4. 打开 DMG，把 `QuotaMonitor.app` 拖入“应用程序”，再启动。
5. 若系统提示来源或安全异常，先核对来源、发布说明与签名状态。不要执行来源不明的移除隔离或关闭 Gatekeeper 命令。

正式发行流程见[发布指南](RELEASING.md)。

## 第一次打开后怎么用

| 想做什么 | 准备与操作 | 应看到什么 |
| --- | --- | --- |
| 查 Codex 剩余额度 | 在当前用户下登录 Codex，打开 QuotaMonitor 的“额度监控”并刷新 | 服务返回的额度与重置时间；若认证或接口失败，可能显示缺失或保留旧数据 |
| 查 DeepSeek 余额 | 在 Codex、Claude 或 cc-switch 中配置有效 DeepSeek 路由，确保凭据可被读取 | 对应账户余额；预计天数取决于可用的本地历史 |
| 查工具 Token | 正常使用目标工具，确保它已写入支持的本地日志；打开“Token 看板” | 本机可读取的统计，不含其他设备或未落盘请求 |
| 看最近变化 | 切换今日 / 7 / 30 / 90 日 / 累计，再选择平台或模型 | 相应时间段的趋势及排行；历史不足时范围可用性受限 |
| 设置常驻 | 按需启用登录后自动启动，选择中文或 English | 下次登录自动运行；也可关闭并从菜单栏退出 |

首次使用没有历史缓存，需要扫描日志。后续启动会先恢复已有统计，再后台更新。额度约每 60 秒刷新，本地 Token 约每 5 分钟刷新；文件变化会合并触发更新，手动刷新可用于检查最新状态。

权限请求可能涉及日志目录或 Codex 钥匙串条目。按具体来源判断是否允许；不要将密钥复制给 Agent，不必为“没有数据”直接授予全部磁盘访问权限。

## 常见问题与排查

| 现象 | 建议操作 |
| --- | --- |
| 找不到 DMG | 当前可能只有源码；按上文构建或交给 Agent。不要把不存在的文件名当成下载入口 |
| 找不到 `swift`、版本不符或 SDK 错误 | 检查 `xcode-select -p` 和 `swift --version`；补齐并选中支持 Swift 6 的工具链 |
| 提示找不到签名证书 | 本地安装使用上文两个 ad-hoc 环境变量；正式分发需要另一套签名和公证流程 |
| 安装后没看到窗口 | 应用入口在 Mac 顶部菜单栏；先确认进程是否运行及菜单栏是否被其他项目遮挡 |
| Codex 额度显示 `--` 或旧值 | 检查同一用户下的 Codex 登录、网络及更新时间，再手动刷新。直接认证路径不可用时会尝试可发现的 Codex app-server，认证兼容性仍可能随版本变化 |
| 不使用 Codex，但想看其他工具 | 可以只用 Token 看板；额度区没有 Codex 数据不代表本地日志统计不可用 |
| Token 是 0 或某工具不出现 | 确认该工具在本机产生过支持的日志、路径和读取权限正确，等待首次扫描完成；没有匹配记录不等于服务商账户从未使用 |
| Claude Desktop 没数据 | 当前实现需要 cc-switch 中实际存在的桌面端请求日志；cc-switch 未运行时应用会将该来源标记为未采集或过期，其他来源不受此条件影响 |
| Cursor / Antigravity 没数据 | 检查[支持清单](DATA_SOURCES.md)中的结构化记录或同步缓存。安装了工具本身不代表这些缓存已存在 |
| 手动刷新后仍与账单不一致 | 对齐时间段、账号、设备及 Token 口径；当前没有完整云账单同步和本地多账号隔离 |
| CPU / 内存持续很高 | 先看是否正在首次扫描或工具持续写日志，避免反复刷新；记录问题发生时长、日志总大小及版本。若持续影响使用，退出应用并提交脱敏问题报告 |
| 删除缓存后重新扫描很慢 | 缓存删除后要重新处理源日志；它不是性能故障的通用解决办法，也无法恢复已删除的源记录 |
| 换账号后历史仍在 | 本地日志和缓存可能包含此前账号记录。当前没有完善的按账号隔离，不要把历史总量认作当前账号账单 |

已加入的耗电优化包括缓存、增量读取、合并文件事件、单实例与按状态重绘；不同机器、日志规模和首轮扫描的资源消耗仍不同。持续高占用需要根据实际进程和样例定位。

## 更新与回退

当前没有内置自动更新器。更新前记录当前提交号，退出应用，并保存有需要的旧应用副本到你指定的备份位置。先检查源码状态：

```bash
git status --short
git rev-parse HEAD
```

只有工作区干净、且你确认要更新当前分支时，执行：

```bash
git pull --ff-only
swift test
./script/security_check.sh
QUOTAMONITOR_ALLOW_ADHOC=1 QUOTAMONITOR_SIGNING_IDENTITY=- ./script/build_and_run.sh --verify
```

有本地改造或出现分叉时，让 Agent 保留修改后处理，不要用强制重置消除冲突。脚本安装成功后不会永久保留旧包；如需回退，请使用自行保存的旧包或在另一目录构建已记录的提交。不同版本可能使用不同缓存结构，回退后应重新核对数据。

## 自定义日志目录

部分工具支持通过启动环境增加数据目录，详见[支持清单](DATA_SOURCES.md)。环境变量必须传给 **QuotaMonitor 进程**；在终端 `export` 后从 Finder 启动，通常不会继承该终端环境。

以 OpenClaw 为例，先退出已有 QuotaMonitor，再将占位路径替换为真实目录后从终端运行：

```bash
QUOTAMONITOR_OPENCLAW_HOME="/absolute/path/to/openclaw-data" /Applications/QuotaMonitor.app/Contents/MacOS/QuotaMonitor
```

这是前台运行方式，需保留该终端进程。额外路径会与默认路径一起扫描，并非关闭默认来源。当前没有为所有工具提供统一的可视化路径配置；登录后自动启动也不会自动继承该终端变量。

## 卸载与数据清理

1. 在设置中关闭“登录后自动启动”，从菜单栏退出 QuotaMonitor。
2. 将 `/Applications/QuotaMonitor.app` 移到废纸篓。
3. 若要清除用量缓存，在 Finder 的“前往文件夹”中打开 `~/Library/Caches/com.cmsjcm.QuotaMonitor/`，确认内容后将该应用缓存目录移到废纸篓。重新安装后需要重新扫描。
4. 缓存外还可能有应用偏好设置：当前应用标识为 `com.cmsjcm.QuotaMonitorStatus3`，旧版使用过 `com.cmsjcm.QuotaMonitorStatus2`、`com.cmsjcm.QuotaMonitorStatus`、`com.cmsjcm.QuotaMonitor`、`com.cmsjcm.QuotaDot`。如需彻底清理，让 Agent 检查属于这些应用标识的偏好项目后再处理。

不要为卸载 QuotaMonitor 删除 `~/.codex`、`~/.claude` 或其他 AI 工具目录；它们属于原工具，可能含完整会话及认证信息。源码文件夹可自行保留；删除源码前先保存你的改造内容。

### macOS 26 状态栏说明

macOS 26 新增了“系统设置 → 菜单栏”中的应用状态项开关。系统关闭该开关后，QuotaMonitor 仍可能在后台运行，但状态栏入口会被隐藏；应用无法绕过这项系统选择。可先尝试在该页面重新开启 QuotaMonitor（注意：本机 2026-09-11 实测关闭→开启并重启 Control Center 与应用后，Status2 仍被屏蔽，多数情况下无效）。

若开关开启后状态项仍不显示（本机 macOS 26.6 曾出现多个历史应用标识被系统屏蔽、开关无法恢复的现象），才使用 `script/assemble_app.sh` 更换 `BUNDLE_ID` 后重装的应急方案。**这是当前机器的兼容性应急手段，不是通用机制，也不应作为正式发布的长期方案**：每次更换应用标识，系统都会把通知权限、登录项和偏好设置识别为另一款应用。更换后请同步更新 `script/build_and_run.sh` 中的 `BUNDLE_ID`，保持两处一致。

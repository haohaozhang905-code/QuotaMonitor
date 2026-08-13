# 发布指南

QuotaMonitor 面向公众发布的 DMG 必须使用 **Developer ID Application** 证书签名，并通过 Apple 公证。Apple Development、Apple Distribution 和 ad-hoc 签名不能替代 Mac App Store 之外的正式分发签名。

## 一次性配置

1. 为发布环境创建并安装 Developer ID Application 证书。
2. 准备用于公证的 App 专用密码或 App Store Connect API Key。
3. 将公证凭据保存到本机钥匙串配置中：

```bash
xcrun notarytool store-credentials QuotaMonitorNotary \
  --apple-id "APPLE_ID" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

不要将签名证书、私钥、密码或公证凭据提交到代码仓库。

## 构建正式版本

```bash
export NOTARYTOOL_PROFILE=QuotaMonitorNotary
export QUOTAMONITOR_VERSION=0.1.0
export QUOTAMONITOR_BUILD_NUMBER=1
./script/package_release.sh
```

脚本会构建发布版本、启用 Hardened Runtime、添加安全时间戳，对应用进行公证并装订公证票据，然后创建并签名 DMG，再打印 SHA-256 校验值。

发布前，应在干净的标准 macOS 用户环境中安装 DMG，并检查：

- 应用能否正常启动
- Codex 官方路由是否正常
- DeepSeek 路由和余额是否正常
- 路由切换后显示是否正确
- 开机启动是否正常
- 卸载流程是否正常

## 本地打包检查

没有发布凭据时，可以检查 DMG 布局：

```bash
./script/package_release.sh --unsigned
```

该命令会生成文件名以 `UNSIGNED.dmg` 结尾的未签名 DMG，只能用于本地检查，不能作为公开版本发布。

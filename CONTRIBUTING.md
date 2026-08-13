# 参与贡献

感谢你帮助改进 QuotaMonitor。

## 提交改动前

1. 先搜索已有 Issue，并尽量让每个改动保持单一目标。
2. 不要上传 `auth.json`、Keychain 导出文件、Access Token、完整用户名或精确位置数据。
3. 修改额度解析逻辑时，请补充脱敏后的 Fixture 或针对性的单元测试。
4. 修改视觉界面时，请提供已移除个人信息的前后截图。

## 开发检查

```bash
./script/security_check.sh
swift test
./script/build_and_run.sh --verify
```

Pull Request 请说明：

- 用户能看到的行为变化
- 额度数据使用的事实来源
- 修改的验证方式

如需新增分析、远程配置或网络服务，请先单独说明隐私影响。不要在未经讨论的情况下加入这些能力。

你的贡献将按照 MIT License 授权。

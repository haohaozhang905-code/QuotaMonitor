# 参与贡献

感谢你帮助改进 QuotaMonitor。

开始前可阅读[安装与构建](docs/INSTALL.md)、[架构与改动边界](docs/ARCHITECTURE.md)、[工具支持清单](docs/DATA_SOURCES.md)和[定制与二次开发](docs/CUSTOMIZATION.md)。新增工具时请区分代码适配与真实环境验证，说明已验证的工具版本及统计边界。

## 提交改动前

1. 先搜索已有 Issue，并尽量让每个改动保持单一目标。
2. 不要上传 `auth.json`、Keychain 导出文件、Access Token、完整用户名或精确位置数据。
3. 修改额度解析逻辑时，请补充脱敏后的 Fixture 或针对性的单元测试。
4. 修改视觉界面时，请提供已移除个人信息的前后截图。

## 规范开发

开始中等以上改动前，请阅读[产品总纲](docs/PRODUCT.md)和[规范开发索引](specs/README.md)。涉及用户界面时还需阅读[设计规范](docs/DESIGN_SYSTEM.md)。改变用户行为、数据口径、持久化、权限、网络、提醒、状态栏或安装流程时，需要建立或更新功能级 `spec.md` 和 `plan.md`。

- `spec.md` 定义用户问题、范围、非目标、需求编号和可观察验收标准。
- `plan.md` 定义架构、迁移、实施阶段、测试、发布与回滚。
- 需求 ID 需要同步到[需求追踪矩阵](docs/TRACEABILITY.md)。
- 公共颜色、字体、间距、状态和组件需要复用设计规范；改变公共设计语言时同步更新规范并提供浅色/深色证据。
- 事后重建的规范必须标明 `provenance: reconstructed`；被替代的规范保留并标记 `superseded`。
- 运行 `./script/verify_sdd_docs.sh` 检查当前规范基线。

## 开发检查

```bash
./script/verify_sdd_docs.sh
bash script/verify_refactor.sh
./script/security_check.sh
swift test
```

`verify_refactor.sh` 使用临时 SwiftPM 缓存并运行测试、应用构建、本地化键校验、安全检查与代码指标统计；它不会安装、替换或启动应用。构建和单测通过不等于真实界面验收。

## 状态栏与应用身份保护

- 状态栏入口由 `Sources/QuotaMonitor/App/QuotaMonitorApp.swift` 创建。修改提醒、Token 规则或页面布局时，不要顺手改状态栏创建、登录项或安装代码。
- `NSStatusItem.autosaveName` 禁止设置：macOS Control Center 可能持久化 blocked 状态，导致进程仍在运行但状态栏入口消失。
- 本地组装、开发构建和发布脚本的 App 名称、版本与 Bundle ID 统一来自 `script/app_config.sh`。当前身份必须保持 `com.cmsjcm.QuotaMonitorStatus4`；不要轮换到 Status3，也不要在其他脚本复制 Bundle ID。
- 如果需求确实涉及状态栏或应用身份，把它拆为独立改动；运行 `script/verify_refactor.sh` 后再获得安装授权，启动真实 App，并用 `script/verify_menu_bar_status.sh <pid> <bundle-id>` 检查 Control Center 已初始化状态项且没有将其加入 blocked list。还需肉眼确认状态栏图标与下拉框。

`QUOTAMONITOR_ALLOW_ADHOC=1 QUOTAMONITOR_SIGNING_IDENTITY=- ./script/build_and_run.sh --verify` 会构建、替换 `/Applications/QuotaMonitor.app` 并启动验证，不能作为常规重构检查；执行前须单独确认安装授权并保存需要保留的旧应用。本地 ad-hoc 签名不等于公开分发所需的签名与公证。

Pull Request 请说明：

- 对应的 Spec ID，或该改动无需 Spec 的原因
- 用户能看到的行为变化
- 额度数据使用的事实来源
- 修改的验证方式
- 自动化、真实应用和视觉验收各自的状态

如需新增分析、远程配置或网络服务，请先单独说明隐私影响。不要在未经讨论的情况下加入这些能力。

你的贡献将按照 MIT License 授权。

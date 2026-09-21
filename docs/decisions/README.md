# 架构决策记录

本目录保存影响多个模块、长期兼容性、数据真实性、安全或发布行为的决策。

## 状态

- `proposed`：等待确认；
- `accepted`：当前有效；
- `superseded`：已被后续 ADR 替代；
- `rejected`：讨论后不采用。

事后根据代码和历史记录补建的 ADR 使用 `provenance: reconstructed`，用于解释当前设计来源。

## 索引

| ADR | 决策 | 状态 |
| --- | --- | --- |
| [0001](0001-token-evidence-boundary.md) | Token 统计只使用可验证字段 | accepted |
| [0002](0002-reminder-ledger-v3.md) | 提醒状态使用规则 ID 与 V3 账本 | superseded |
| [0003](0003-status-item-identity.md) | 状态栏身份集中配置并禁止 autosaveName | accepted |
| [0004](0004-reminder-ledger-v5.md) | V5 账本按确认的额度补充周期去重 | accepted |

## 新增 ADR 的条件

- 改变数据定义或事实来源；
- 引入新的持久化版本或迁移方向；
- 改变权限、凭据、隐私或网络边界；
- 改变状态栏、应用身份、安装和发布策略；
- 选择会长期限制架构的方案。

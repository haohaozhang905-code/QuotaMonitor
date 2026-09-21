# 提醒机制 V1.1 任务与证据

> Spec：[`QMR-001`](spec.md)<br>
> Plan：[`QMR-001-PLAN`](plan.md)<br>
> 状态：Implemented，真实应用验收仍有待完成项

## 状态说明

- `Done`：实现和相应自动检查已有证据；
- `Partial`：实现存在，仍缺指定的运行或视觉证据；
- `Pending`：尚未实现或尚未开始；
- `Blocked`：需要权限、外部环境或用户输入。

## 产品与规范

| 任务 | 状态 | 证据 |
| --- | --- | --- |
| 明确目标、范围和非目标 | Done | `spec.md` |
| 为需求建立 REM-001～REM-011 编号 | Done | `spec.md` |
| 建立技术执行计划 | Done | `plan.md` |
| 建立需求、代码、测试追踪 | Done | `docs/TRACEABILITY.md` |
| 将历史提醒设计与当前 Spec 关联 | Done | `docs/REMINDER_PRODUCT_DESIGN.md` |

## 规则与状态

| 任务 | 状态 | 证据 |
| --- | --- | --- |
| 统一规则目录和稳定 ID | Done | `ReminderRuleCatalog`、规则目录测试 |
| 额度 30%/5% 分档与跨档 | Done | `ReminderRuleEvaluator`、阈值测试 |
| 额度颜色与提醒分档统一 | Done | `QuotaRiskPolicy`、`QuotaHealth`、概览/下拉框与提醒 Tone 测试 |
| 5 小时/周额度重置识别 | Done | 窗口变化条件与重置测试 |
| 用户主动重置抑制 | Done | 同轮重置机会与双额度测试 |
| 重置机会逐项到期提醒 | Done | 到期窗口和 occurrence 测试 |
| DeepSeek 恢复线 | Done | 余额 hysteresis 测试 |
| Token 最高里程碑 | Done | 周期里程碑测试 |
| Token 文件事件首事件定时与扫描后补刷 | Done | `TokenRefreshWakeupState` 状态测试 |
| Codex 额度与 DeepSeek 余额并行刷新 | Done | `QuotaStore.refresh()` 独立并行任务 |
| 休眠越过 5 小时窗口后只提醒一次 | Done | 休眠恢复、持久化重启与窗口连续后移回归测试 |
| 连续 100% 时服务端重置时间后移保持静默 | Done | 恢复边沿状态与 100% 时间变化测试 |
| V1～V4→V5 账本迁移与持续漂移去重 | Done | 迁移实现、旧键保留及完整 Swift 测试 |
| 熄屏、锁屏、醒后新鲜快照门控 | Partial | 状态与投递竞态自动化测试通过；目标 macOS 锁屏事件及实际投递待真机验证 |

## 投递与设置

| 任务 | 状态 | 证据 |
| --- | --- | --- |
| 系统通知投递 | Done | `ReminderDeliveryController` |
| 应用内卡片降级 | Done | `ReminderDeliveryController`、`ReminderToastView` |
| 8 秒消失、悬停暂停、点击跳转 | Done | 投递控制器与 Toast 交互代码 |
| 系统通知授权状态同步 | Done | `ReminderSettings` 及设置测试 |
| 卡片坐标限制在可见屏幕 | Done | `toastOrigin` 使用 `visibleFrame` 夹紧 |
| 主屏与多屏真实视觉验证 | Partial | 需在当前安装 App 中补验收记录 |

## 自动化和发布

| 任务 | 状态 | 证据 |
| --- | --- | --- |
| 规则、迁移、精确 2 亿边界、刷新唤醒、文案和设置测试 | Done | 2026-09-21：14 项 XCTest、132 项 Swift Testing 全部通过 |
| 本地化键一致性 | Done | `script/verify_refactor.sh` |
| 凭据与个人信息扫描 | Done | `script/security_check.sh` |
| SDD 必备文件和需求编号门禁 | Done | `script/verify_sdd_docs.sh` |
| CI 执行 SDD 文档检查 | Done | `.github/workflows/ci.yml` |
| 当前安装 App 的通知与卡片回归 | Partial | 需要安装授权和真实系统状态 |

## 后续版本候选

以下事项不直接加入 V1.1，应新建 Spec：

- 自定义阈值和静默时段；
- 提醒历史和逐条已读；
- 预算告警；
- 更完整的多屏自动化测试；
- 自定义供应商余额提醒。

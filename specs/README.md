# QuotaMonitor 规范开发索引

本目录保存功能级产品规范和技术执行计划。项目定位与长期边界见 [`docs/PRODUCT.md`](../docs/PRODUCT.md)，公共视觉、交互与界面状态遵循 [`docs/DESIGN_SYSTEM.md`](../docs/DESIGN_SYSTEM.md)。

## 文档分工

| 文件 | 回答的问题 | 主要读者 |
| --- | --- | --- |
| `spec.md` | 为什么做、为谁做、做什么、怎样算完成 | 产品、设计、研发、测试 |
| `plan.md` | 怎么实现、分几步、改哪些模块、怎样迁移和回滚 | 研发、测试、维护者 |
| `tasks.md` | 当前做到哪里、每项任务有什么证据 | 项目负责人、协作者 |
| `acceptance.md` | 哪些验收已通过、哪些仍待真实环境确认 | 产品、测试、发布负责人 |

设计规范不按功能重复复制。功能 Spec 只写本功能的界面状态和特殊交互；公共颜色、字体、间距、组件、无障碍与视觉验收规则统一由 `docs/DESIGN_SYSTEM.md` 管理。

## 状态

- `draft`：仍在讨论，不授权实现；
- `accepted`：范围和验收已确认，可以执行；
- `implemented`：代码已实现，验证可能尚未完成；
- `verified`：规定的自动化和真实环境验收均已完成；
- `superseded`：已被新版替代，保留作决策历史。

`provenance: reconstructed` 表示文档根据现有代码、提交和验证记录事后重建。它用于建立当前基线，不能证明历史开发严格遵循了先 Spec 后编码。后续版本应在实现前进入 `accepted`。

## 范围规则

功能级 Spec 应围绕一个可独立验收的用户结果。出现以下信号时需要拆分：

- 包含多个无直接依赖的用户目标；
- 无法用一组清晰场景判断完成；
- 无法独立发布或回滚；
- 计划跨越多个版本且没有稳定边界。

局部文案、注释和不改变语义的样式修复可以在任务或 Pull Request 中记录。数据口径、持久状态、权限、网络、核心交互和跨模块改动需要 Spec。

## 当前规范

| ID | 功能 | 状态 | Spec | Plan | 验收 |
| --- | --- | --- | --- | --- | --- |
| `QMR-001` | 提醒机制 V1.1 | implemented / partially verified | [spec.md](001-reminder-v1.1/spec.md) | [plan.md](001-reminder-v1.1/plan.md) | [acceptance.md](001-reminder-v1.1/acceptance.md) |
| `QMV-001` | 导航与下拉框玻璃材质 | implemented / visual pending | [spec.md](002-glass-surfaces/spec.md) | [plan.md](002-glass-surfaces/plan.md) | [acceptance.md](002-glass-surfaces/acceptance.md) |

新功能可从 [`_template`](_template) 复制 `spec.md`、`plan.md`、`tasks.md` 和 `acceptance.md`，确认范围后再将状态从 `draft` 更新为 `accepted`。

## 历史规范

UI 改造曾在提交 `d416fb9` 中包含 `docs/design-spec.md` v4 和 `docs/implementation-plan.md` v1，后续在 `0b24094` 中删除。它们记录了设计语义、分阶段实现、风险和完成定义，但已经不能代表当前实现。

- [历史设计规范](https://github.com/haohaozhang905-code/QuotaMonitor/blob/d416fb9bc288239b42ed899ca07b1339eb9d6f1b/docs/design-spec.md)
- [历史技术计划](https://github.com/haohaozhang905-code/QuotaMonitor/blob/d416fb9bc288239b42ed899ca07b1339eb9d6f1b/docs/implementation-plan.md)

保留这段来源是为了呈现规范演进。历史 v4 中仍有效的信息架构、业务维度、状态模型、窗口行为和数据边界，已经按当前代码重新核对并合并到[当前设计规范](../docs/DESIGN_SYSTEM.md#11-历史来源与合并结论)；旧色板、旧圆角和已退役布局仍只属于历史版本。若后续恢复为仓库内归档，应标记 `superseded`，不能重新声明为当前唯一依据。

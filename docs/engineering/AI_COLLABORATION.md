# AI 协作与工程复盘

> 状态：Active<br>
> 最近更新：2026-09-13<br>
> 说明：以下案例依据仓库代码、提交与本地协作记录整理；未完成的验证会明确保留

## 1. 协作方法

QuotaMonitor 使用编程 Agent 参与调研、需求拆解、代码实现、测试和文档维护。项目采用以下闭环：

```text
用户问题或异常
  → Agent 提出可验证假设
  → 检查真实字段、运行状态或界面
  → 用户确认范围和取舍
  → 修改代码与测试
  → 将已复现问题转成自动保护
  → 分别记录自动化、真实应用和视觉验收
```

AI 可以加速探索和实现，字段语义、用户体验取舍、权限操作与最终验收仍需要证据和明确责任边界。

## 2. 案例一：纠正 WorkBuddy Token 字段语义

### 现象

早期尝试使用 `session_usage.used` 表达 WorkBuddy 累计 Token，结果明显偏低。

### 排查与根因

协作中回到真实本地结构核对，发现该字段更接近上下文窗口占用，存在窗口上限，无法直接代表累计吞吐。随后出现的新版本 trace 将调用级 usage 放入 generation span 的 `toolOutput`，需要按实际结构解析和去重。

### 处理

- 放弃用上下文占用推算累计 Token；
- 在专用 `WorkBuddyTraceClient` 中保留来源语义；
- 只读取 generation usage 中明确的输入、缓存和输出字段；
- 对追加写入、跨块边界、假标记和缓存继续读取增加测试；
- 在数据源文档中说明未知字段不能靠文本长度或上下文上限补估。

### 防复发机制

- `docs/PRODUCT.md` 与 `AGENTS.md` 固化“未知字段不推估”；
- 来源专用解析不合并进通用扫描器；
- 数据来源变更必须补最小脱敏 Fixture 或针对性测试；
- 面试或文档表达区分“本地可验证 Token”和“上下文/积分代理值”。

### 个人判断

这次调整的关键判断是接受已有口径不可靠，重新验证原始结构，并让实现随证据变化。速度让位于数据真实性。

## 3. 案例二：状态栏入口消失转成硬门禁

### 现象

应用进程仍在运行，但 macOS 菜单栏入口消失，普通重启也可能无法恢复。

### 排查与根因

问题与 `NSStatusItem.autosaveName` 触发的 Control Center 持久化状态有关。系统可能记住 blocked 状态，使代码和构建都正常时仍看不到入口。

### 处理

- 禁止设置 `NSStatusItem.autosaveName`；
- 将 App 名称、版本与 Bundle ID 集中到 `script/app_config.sh`；
- 状态栏和应用身份改动必须独立处理；
- 安装后检查 Control Center 状态，并肉眼确认图标和下拉框。

### 防复发机制

`script/security_check.sh` 和 `script/verify_refactor.sh` 会搜索被禁止的属性并检查固定应用身份。Agent 即使再次生成相同代码，也会在进入发布前失败。

### 个人判断

只修复一次源码无法覆盖系统持久状态。最终方案同时约束代码、构建配置、运行检查和人工视觉确认。

## 4. 案例三：提醒卡片已创建但位于屏幕外

### 现象

测试提醒执行后没有报错，规则测试也通过，但用户在桌面上看不到应用内卡片。

### 排查与根因

进一步检查 `NSPanel` 实际坐标，发现菜单栏附近的计算可能产生负数纵坐标。问题发生在窗口几何和屏幕坐标层，规则测试无法发现。

### 处理

- 定位函数读取状态栏按钮所在屏幕的 `visibleFrame`；
- 横纵坐标均夹紧到可见范围；
- 没有可靠按钮或屏幕信息时使用右上角安全位置；
- 在产品规范中把主屏、多屏和边缘位置列为独立验收项。

### 当前边界

代码已经包含可见区域夹紧。当前记录仍缺专用多屏几何自动化测试，以及在最新安装 App 中覆盖所有位置的视觉证据，因此保持 `Partial`。

### 防复发机制

- `acceptance.md` 不允许用规则测试代替窗口视觉验收；
- 后续计划增加纯几何测试入口，覆盖屏幕原点、负坐标屏幕和多卡片堆叠；
- 真实应用验收记录构建版本、屏幕布局与截图。

## 5. 案例四：控制 AI 改动范围

### 现象

视觉、提醒和数据源任务容易同时触碰大型 View、Store、安装脚本和状态栏入口，产生与目标无关的回归。

### 处理

- 通过 Spec 明确非目标和保护边界；
- 使用 Plan 指定优先入口、迁移和测试；
- 开始前检查脏工作区，保留无关修改；
- 颜色、几何、Hover 和数据语义分别验收；
- 已确认的系统级问题转成安全脚本与贡献规范。

## 6. 对编程 Agent 的固定要求

1. 先说明正在解决的用户结果和改动边界；
2. 对不稳定或不明确的字段先做只读验证；
3. 给出失败模式、降级和回滚，不只写正常路径；
4. 测试覆盖已复现问题，避免只测试新抽象；
5. 汇报时分开说明代码、自动化、安装和视觉状态；
6. 无法验证时保留 `Pending` 或 `Partial`，不补写成功结论。

## 7. 可展示证据

- 规范入口：[`specs/README.md`](../../specs/README.md)
- 提醒 Spec 与 Plan：[`specs/001-reminder-v1.1`](../../specs/001-reminder-v1.1)
- 需求追踪：[`docs/TRACEABILITY.md`](../TRACEABILITY.md)
- 状态栏保护：[`script/security_check.sh`](../../script/security_check.sh)
- 综合验证：[`script/verify_refactor.sh`](../../script/verify_refactor.sh)
- WorkBuddy 边界测试：[`Tests/QuotaMonitorTests/LocalTokenSourceTests.swift`](../../Tests/QuotaMonitorTests/LocalTokenSourceTests.swift)
- 提醒规则与迁移测试：[`Tests/QuotaMonitorTests/ReminderRuleTests.swift`](../../Tests/QuotaMonitorTests/ReminderRuleTests.swift)

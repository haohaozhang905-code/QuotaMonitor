# README 截图维护

README 当前只展示 QuotaMonitor 的真实运行截图，不再使用重绘、拼接或带外部标注的合成展示图。截图中的额度、余额、Token 数量和时间仅代表拍摄当时的账户与本机记录。

## 截图清单

| 界面 | 浅色模式 | 深色模式 |
| --- | --- | --- |
| 状态栏与下拉框 | `menu-dropdown-light.png` | `menu-dropdown-dark.png` |
| 主面板概览 | `overview-light.png` | `overview-dark.png` |
| Token 看板 | `token-dashboard-light.png` | `token-dashboard-dark.png` |
| 设置 | `settings-light.png` | `settings-dark.png` |

README 使用 HTML `<picture>` 根据阅读者的 GitHub 主题自动选择浅色或深色截图，并在可展开区域提供一张 `screenshots-overview.png` 深浅色拼接总览图（上排浅色、下排深色，四页面并排）。更新原图后需重新生成拼接图。

## 更新规则

1. 浅色和深色截图使用同一版本、相同窗口尺寸和同一组测试数据，避免读者误把数据差异当成主题差异。
2. 状态栏截图需要同时保留菜单栏中的额度 / 余额槽位和展开后的下拉框，完整覆盖两种入口形态。
3. 主面板至少覆盖概览、Token 看板和设置；界面结构或关键文案变化时同步替换对应的明暗两张图片。
4. 保留原始比例，不在截图中重绘控件、数字或图表。提交前检查图片尺寸、README 引用和明暗主题下的可读性。
5. 截图不得包含认证信息、API Key、完整对话正文或可识别的私人路径内容。

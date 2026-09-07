# README 展示图维护

展示图使用内置图片编辑工具，以仓库内真实截图为输入制作。原始截图保留，便于核对数据与界面细节。放大镜、外部文字与引导线属于说明图，不代表应用新增了这些功能。

## 三种形态

输出：`three-surfaces-annotated.png`

输入：`menu-bar-preview.png`、`overview-preview.png`

### 编辑提示词

```text
Use case: compositing.
Create a polished Chinese GitHub README product showcase by EDITING AND COMPOSITING the supplied real QuotaMonitor screenshots. Output a high resolution landscape image approx 2400x1600. This is screenshot annotation, not UI redesign. Preserve all source UI typography, exact numbers, icons, data and proportions; use intact screenshot regions, do not invent controls or redraw charts.
Image 1: menu-bar-preview.png is source for TWO different product states: the narrow top macOS status bar and the dropdown below it. Image 2: overview-preview.png is the real main panel.
Visual style: sophisticated clean editorial product demonstration, very light warm grey canvas, dark charcoal type, restrained violet accent matching the app icon, generous white space, hairline connectors, subtle real screenshot shadows. No decorative objects, no laptop mockups, no gradients, no marketing badges. Chinese sans-serif, clear large annotations readable at README width.
Top left large exact heading: "额度，抬眼就能看到"
Subtitle: "状态栏 → 下拉框 → 主面板"
Make the STATUS BAR the strongest visual focus in the upper third. Show a horizontal crop of the ORIGINAL TOP 58 PIXELS of image 1, enlarged, retaining original muted desktop background and authentic original icon + 19% + icon + ¥7.27. Exclude unrelated icons at right by cropping after ¥7.27. Surround this crop with a thin violet focus outline. Give it a large polished round magnifier inset that duplicates and enlarges the ORIGINAL 19% and ¥7.27 content (fit both values, do not crop numbers), with a slender connector from source to magnifier. Outside, exact label "01 状态栏" and caption "剩余额度与余额，随时可见". This is an editorial zoom annotation, not an app magnifier feature.
Lower half: left real dropdown image 1 cropped below the statusbar, about 430px wide; right real overview screenshot 2 about 1200px wide, both proportional and clear, no perspective. Labels above each: "02 下拉框" with "点击查看额度、重置时间和今日用量"; "03 主面板" with "打开完整面板，查看概览与分时趋势". A subtle connector from top bar to dropdown labelled "点击", then a subtle connector from dropdown's actual "打开主面板" row to the right main window labelled "打开主面板". Outline dropdown's actual quota rows and its actual "打开主面板" row in restrained violet. Keep connectors outside important UI text. Main panel should remain visually subordinate to status-bar zoom, despite larger width. Show all three states exactly once plus one magnifier inset. Do not add any unrelated settings screenshot. Keep all labels in the outer canvas, never obscure real data. Small footer exact text: "真实界面截图 · 局部放大与标注仅用于展示".
Ensure attractive balanced composition and large readable status bar.
```

## 图表解读

输出：`token-charts-annotated.png`

输入：`token-dashboard-preview.png`

### 编辑提示词

```text
Edit the supplied real QuotaMonitor screenshot into a clean annotated product explainer image, 1536x1024 landscape. Keep the existing dark UI, charts, numbers, labels and proportions unchanged. Place the screenshot at about 78% canvas width on a warm off-white canvas. Add headline "用量花在哪，展开看清楚". Add three thin violet outline highlights and matching numbered captions in the right margin, with neat leader lines: "01 时间范围" / "近 7 / 30 / 90 日与累计" pointing to the actual top-right time selector; "02 分析维度" / "按平台或模型切换趋势" pointing to actual chart toggle; "03 用量分布" / "查看各平台与模型占比" pointing to the actual bottom ranking panels. Add a small rectangular magnified inset of the actual "按平台 / 按模型" toggle beneath caption 02, with violet border. Editorial typography, generous whitespace, no extra app controls, no settings, no additional graphs. Footer "基于真实截图制作 · 放大与标注仅用于展示". Preserve authentic screenshot details.
```

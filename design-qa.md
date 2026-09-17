# NOTE4 白色机身视觉核验

**Source visual truth**

- 936 × 946 px，正面白色 NOTE4 实机参考。

**Rendered implementation**

- 桌面视口 1440 × 900 CSS px、完整页面视口 1440 × 5200 CSS px、移动端视口 500 × 1100 CSS px；deviceScaleFactor 1。
- 状态：首页默认状态、浏览器支持刷机状态、四张视图预览默认状态。

**Full-view comparison evidence**

- 实现已经从黑色横向显示器外框改为近方形白色 NOTE4：白色圆角机身、内凹 4:3 屏幕、左下扬声器孔、右下状态灯与圆形按键均与参考图的硬件识别特征一致。
- 首页、四张界面卡片、GitHub 头图与网页分享图使用同一机身素材，外观没有跨区域漂移。
- 400 × 300 屏幕内容完整贴合显示开口，没有遮挡机身边框或控制区。
- 500 px 移动端视口下无水平溢出，设备完整可见，文字与刷机按钮未被裁切。

**Focused region comparison evidence**

- 单独核对了屏幕开口：网页内容位于机身素材的 13.65% / 10.25% 起点，宽 72.7%、高 54.25%，保留了参考图中的浅灰内凹边缘。
- 单独核对了下方控制区：扬声器孔、状态灯与圆形按键保持在屏幕之外，比例和左右位置与参考一致。

**Required fidelity surfaces**

- Fonts and typography：网页继续使用系统 SF / 苹方字体，标题层级、正文行高与屏幕内文字清晰度保持原设计；未因机身替换发生缩放或换行异常。
- Spacing and layout rhythm：机身改为 1:1 外框，屏幕维持 4:3；桌面与移动端留白均衡，预览卡片之间的节奏一致。
- Colors and visual tokens：机身采用白、浅灰与黑色控制元素，和白色实机参考一致；页面仍保留 Apple 风格的中性灰与系统蓝。
- Image quality and asset fidelity：机身为基于实机参考生成的高分辨率独立图片资产，没有用 CSS 图形近似扬声器、按键或外壳。
- Copy and content：产品名、NOTE4 黑白版兼容说明、Apple 生态联动文案与既有版本一致。

**Findings**

- 没有剩余 P0、P1 或 P2 问题。
- P3：参考图含产品说明连线，而网页刻意省略标注，以免与刷机主操作争夺注意力；这是可接受的展示场景差异。

**Comparison history**

- 初始问题：旧版使用黑色横向边框，与白色 NOTE4 实机明显不符（P1）。
- 修复：制作并接入统一的白色 NOTE4 机身素材，更新首页、四张预览卡片、GitHub 头图和 Open Graph 分享图。
- 修复后证据：硬件颜色、机身比例及下方控制区已经与参考图一致。

**Implementation checklist**

- [x] 首页主视觉改为白色 NOTE4。
- [x] 四张界面预览改为白色 NOTE4。
- [x] GitHub README 头图改为白色 NOTE4。
- [x] 网页分享缩略图改为白色 NOTE4。
- [x] 核验桌面、完整页面和移动端布局。

final result: passed

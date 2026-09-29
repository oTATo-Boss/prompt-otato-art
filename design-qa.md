# oTATo prompt · 设计对照 QA

**final result: passed**

本报告的截图与通过结论对应最初交付版本。2026-09-29 新增的“黑白反色”“备忘录黄”高亮配色，以及由 macOS 系统图标外观选择的黑、白透明底线稿尚未纳入这些截图，等待用户在新测试包中体验反馈。

本报告将 34 页 PRD 第 28–33 页的原始视觉稿（见下表源图），与隔离测试库中运行的 macOS 原生应用逐屏比较。资料库、新建页、快速搜索浮层、设置来自整合构建的真实截图；编辑器在最后一次整合构建重新实拍。菜单栏使用从同一交付源码复制的、未改动 MenuBarView 组件独立预览渲染，尚未取得系统状态栏弹层的直接截图。资料库中的 12 条示例与设计稿中的 128 条、排序、时间戳和收藏数量不同，只按布局和资产呈现比较。

## Findings

最终六屏对照没有剩余可操作的 P0/P1/P2 静态视觉差异。[菜单栏最终组件并排](qa-evidence/menu-comparison-component-final3.jpg)中两组“全部 >”已补齐、列表高度随内容收紧；[编辑器最终并排](qa-evidence/editor-comparison-final4.jpg)中标题下恢复浅底标签胶囊和“+”。编辑器“+”通过 CUA AX 点击后出现“输入标签”及“添加”弹出窗口，证实入口可达。菜单栏截图是组件预览，不证明状态栏图标点击、弹层定位、关闭主窗口后交互或菜单栏复制。900 × 620 pt 内容区已在同源码临时小窗构建检查，但交付 Bundle ID 本体的手动缩窗、真实状态栏弹层和跨应用热键仍缺直接证据。

## 对照证据与归一化

| 屏幕 | 视觉真值 | 最终实现 | 全图并排 | 局部并排 | 截图状态 |
| --- | --- | --- | --- | --- | --- |
| 资料库 | [源图](qa-evidence/prd-library-source.jpg) | [干净窗口截图](qa-evidence/library-implementation-final-clean.png) | [对照](qa-evidence/library-comparison-final3.jpg) | [顶部与首行](qa-evidence/library-focused-final3.jpg) | 浅色、网格、12 条隔离演示数据、无查询 |
| 编辑器 | [源图](qa-evidence/prd-editor-source.jpg) | [应用截图](qa-evidence/editor-implementation-final4.png) | [对照](qa-evidence/editor-comparison-final4.jpg) | [标题、工具栏与首行](qa-evidence/editor-focused-final4.jpg) | 浅色、沙漠 Prompt、Markdown 编辑、Inspector 展开 |
| 新建页 | [源图](qa-evidence/prd-create-source.jpg) | [应用截图](qa-evidence/create-implementation-final.png) | [对照](qa-evidence/create-comparison-final3.jpg) | [标题与表单](qa-evidence/create-focused-final3.jpg) | 浅色、空白新建；源稿正文是示例占位 |
| 快速搜索浮层 | [源图](qa-evidence/prd-global-search-source.jpg) | [浅色最近列表](qa-evidence/global-search-implementation-final3.png)、[深色最近列表](qa-evidence/global-search-dark-final.png) | [浅色对照](qa-evidence/global-search-comparison-final3.jpg) | [顶部与前三行](qa-evidence/global-search-focused-final3.jpg) | 源稿深色、查询“人物”、6 行；实现最近 4 行，无查询 |
| 设置 | [源图](qa-evidence/prd-settings-source.jpg) | [应用截图](qa-evidence/settings-implementation-final.png) | [对照](qa-evidence/settings-comparison-final3.jpg) | [顶部四组](qa-evidence/settings-focused-final3.jpg) | 浅色、同一主窗口六组概览、12 条演示数据；窗口失焦时红黄绿按钮灰显 |
| 菜单栏组件 | [源图](qa-evidence/prd-menu-bar-source.jpg) | [同组件独立预览](qa-evidence/menu-component-preview-final3.png) | [组件对照](qa-evidence/menu-comparison-component-final3.jpg) | [顶部与最近项](qa-evidence/menu-focused-component-final3.jpg) | 源稿深色、4 最近 + 4 收藏；预览深色、4 最近 + 3 收藏；**非真实状态栏弹层** |

主窗口实现截图均为 **2560 × 1640 px，@2x，逻辑视口 1280 × 820 pt**。并排图左右各缩到 1280 × 820 px：资料库源图 1536 × 1024 px，裁切 (34,48)–(1502,969)；编辑器、新建、设置源图均为 1448 × 1086 px，分别裁切 (32,69)–(1417,1010)、(34,79)–(1415,989)、(32,45)–(1417,1043)。源稿只提供光栅像素，未标注点密度；裁切后为比较布局归一化，编辑器等会产生少量非等比缩放，不据此做像素级尺寸结论。局部图从各自归一后的同一顶部高度截取。

浮层源图 1448 × 1086 px，裁切 (394,85)–(1055,998)，为 661 × 913 px；最终应用浅色浮层 1280 × 1104 px，@2x，即 640 × 552 pt。全图并排以 **661 px 同宽且保持比例**排列，右侧未填满的纵向空间保持空白，没有拉伸。深色实拍仅检查主题可读性；由于查询与结果集不同，没有拿它虚构同状态像素比较。菜单栏源图 1358 × 1019 px，裁切弹层 (482,63)–(1058,965)，为 576 × 902 px；最终组件预览截图 2560 × 1640 px，@2x，裁切预览容器 (848,214)–(1712,1490)，缩到 576 px 同宽并保持比例。这是可比较的组件内容区域，不包含真实状态栏定位与外部桌面。两个源稿的桌面壁纸均不视为应用资产。

用于应用实拍的隔离资料库位于测试机的 `~/Library/Containers/art.otato.prompt/Data/Library/Application Support/oTATo-QA-FinalClean-20260928`。它仅供视觉验证，用户首启空库与真实资料库不受该数据计数约束。

## 900 × 620 pt 内容区响应检查

为避免 CUA 在交付应用上拖窗失败，另用从最终交付源码复制的临时构建检查：仅将 WindowGroup 默认内容尺寸设为 900 × 620 pt，并将 Bundle ID 改为 art.otato.prompt.qa900；交付源码和 DMG 未改。新 Bundle ID 沙盒不能读取旧容器中的演示库，第一次启动明确报 Sandbox access to file-read-data denied，因此把**隔离演示库的副本**放入 qa900 自己的容器后重启。没有接触真实用户默认库。

该临时实例的四张 CUA 原始截图均为 **1800 × 1344 px，@2x，即外窗 900 × 672 pt**。外窗比设定的 900 × 620 pt 内容尺寸高 52 pt；可见原生标题栏/工具栏区域，故不把原始截图误称为 1800 × 1240 px，也不声称在交付 Bundle ID 上实际拖动到 900 × 620 外窗。PRD 未提供此小窗尺寸的对应视觉稿，本节只检查响应布局与主要控件可达性。

| 状态 | 证据 | 实际观察 |
| --- | --- | --- |
| 资料库 | [小窗网格](qa-evidence/library-compact-900x620.png) | 变为两列卡片，搜索、网格/列表切换、新建、标签筛选与固定“+”可见；侧栏和卡片区各自滚动，未见控件相撞或横向裁断。 |
| 新建页顶部 | [小窗新建](qa-evidence/create-compact-900x620.png) | 左右卡片并存，标题/标签/格式/正文与固定取消、创建按钮可见；四模板位于首屏以下。 |
| 新建页滚动后 | [模板可达](qa-evidence/create-compact-scrolled.png) | CUA 对左侧滚动区执行公开的 Scroll Down 辅助动作后，四模板在两列中完整显示，固定页脚保持可见；右侧封面、变量和收藏卡仍在。 |
| 编辑器 | [小窗编辑](qa-evidence/editor-compact-900x620.png) | 标题、标签、“+”、正文与行号、右侧 Inspector 和底部预览/导出/复制均可见；正文按窄列换行并在独立滚动区内。 |
| 设置 | [顶部](qa-evidence/settings-compact-900x620.png)、[滚动后](qa-evidence/settings-compact-scrolled.png) | 六组概览在窄窗改为单列滚动；通用/快捷键在顶部，编辑器/数据与同步在滚动后可见，控件没有交叠。 |

这六张图均是系统深色主题下的临时构建实拍；测试库位于 `~/Library/Containers/art.otato.prompt.qa900/Data/Library/Application Support/oTATo-QA-Compact-20260929`。该检查覆盖窄窗主要信息与滚动，不代替在交付 Bundle ID 应用上实际拖动、文字放大或 VoiceOver 的发布验收。

## 五项必查面

| 面向 | 最终可见结论 |
| --- | --- |
| 字体与排版 | 六屏中文均能阅读，未见缺字或错误字体回退。资料库卡片标题、日期、标签内边距和编辑器正文的层级已经接近源稿；行号与蓝色 Markdown 标题可见。设置六组标题与说明形成双层排版。菜单栏来源和预览的行标题/标签密度接近；预览的真实字级不能证明系统弹层最终点密度。 |
| 间距与布局节奏 | 资料库四列、三行可视密度、侧栏约 240 pt、顶部筛选固定“+”与设计稿基本同构。编辑器工具栏和正文容器已回到设计稿的纵向落点，Inspector 约 300 pt，封面按钮和页脚操作已放大，标题下标签也恢复浅底胶囊。新建左右卡片、三块右栏、单行四模板与字段计数可见。设置恢复主窗口内六组两列概览。浮层随结果数量缩高；菜单组件按实际行数收紧高度。小窗临时构建中资料库为两列、设置为单列，模板经滚动可达，未见主要控件碰撞。 |
| 颜色与视觉 token | 浅色应用使用原生灰白控件，源稿有更明显的淡蓝材质，属于轻微 P3 漂移；状态色与深色正文对比充分。[深色资料库](qa-evidence/library-dark-final.png)和[深色浮层](qa-evidence/global-search-dark-final.png)真实截图中标题、标签、封面与选中行可读。深色浮层偏石墨灰，源稿偏深蓝，数据/背景材质不同，不给 P2 像素判级。 |
| 图像质量与资产 | 演示封面使用与源稿相同主题的真实图像，未见明显压缩模糊或遮罩光晕；无封面卡片提供正文预览。浮层、菜单预览有真实封面缩略图与文档占位，品牌 Logo 保持可识别。菜单预览首项没有封面是该 QA Prompt 的数据状态，不是把有图源稿换成手绘图。 |
| 文案与内容 | “所有提示词”“新建 Prompt”“复制 Prompt”“最近使用”“收藏”等核心文案连贯；菜单两组右端“全部 >”已可见。12/128、日期、收藏 3/4 与排序是演示库差异。源稿新建正文有示例文字，应用为空白，不能把留白判为缺陷。源稿快捷键提示与已批准 Option+Space 计划不同，以计划为准。设置的 iCloud 为本轮范围外；自动保存必须开启，应用使用“始终开启”文案。 |

## 状态、交互与验收边界

- 最终构建通过 CUA 实际打开资料库卡片、返回资料库、打开新建与设置，并从应用的 Prompt 菜单打开搜索浮层；设置 AX 树显示“全局快捷键已启用”。这不是从别的前台应用触发 Option+Space 的证据。
- 深色主题在设置中选中后拍摄资料库和浮层，随后恢复浅色，AX 树确认“浅色”已选中。深色资料库左上曾出现系统紫色悬浮胶囊；最终浅色资料库已重拍为[干净图](qa-evidence/library-implementation-final-clean.png)，没有把该系统覆盖物判为应用缺陷。
- 浮层的浅色最近列表、深色最近列表与源稿的“人物”六条查询不是同一状态，不能据此判断第六行遗漏、搜索排序、深色半透明度或焦点归还。早前另有[浅色“黑白”搜索结果](qa-evidence/global-search-results-final.png)，只证明搜索结果视觉结构，不是源稿查询复现。
- CUA 的应用窗口截图不含 macOS 状态栏图标，绑定 SystemUIServer 返回 -10005 timeoutReached；因此独立预览只证明交付代码中 MenuBarView 的渲染。系统状态栏真实弹层、关闭主窗口后复制、跨应用热键、方向键/Enter/Esc/焦点归还仍需手工或可访问的 GUI 环境验证。
- 在交付 Bundle ID 应用上直接拖到 900 × 620 pt 时，CUA 曾返回 windowNotFoundAtPosition((421.0, 1166.0))；随后完成了上文所述的**同源码临时小窗构建**响应检查。两者证据范围不同，不宣称交付二进制的实际拖窗操作已通过。VoiceOver 路径与放大文字仍无直接实拍证据。
- 新建页顶栏没有源稿中资料库的搜索、视图切换与重复新建按钮；当前顶栏保留“返回”和页面标题，使未保存草稿成为聚焦上下文，作为已接受的交互取舍。标题和标签计数、四模板说明已在最终图实证。编辑器顶栏也保留聚焦模式，标题下标签和添加入口已在最后一轮补齐。
- 同组件临时预览的“查看全部最近使用”“查看全部收藏”在 AX 树中是按钮。点击前者后预览窗口未切换；预览本身不含真实主窗口导航环境，因此只确认视觉与可访问入口，不将此作为端到端导航通过的证据。

## 迭代记录

1. 资料库早期的[并排图](qa-evidence/library-comparison.jpg)显示无封面预览过浅、卡片信息区偏短和标签“+”混在滚动列表内。改为深色正文预览、信息区竖向 padding 8 → 15 pt、固定可见的独立“+”入口后，[中间版](qa-evidence/library-comparison-final.jpg)与[final2](qa-evidence/library-comparison-final2.jpg)显示三行落点及入口已修正。
2. [早期编辑器对照](qa-evidence/editor-comparison-before.jpg)显示正文小、工具栏过高、无独立编辑容器及行号/标题色。提高编辑字号、调整顶栏与 Inspector 宽度、恢复行号和蓝色 Markdown 标题后，[final2 对照](qa-evidence/editor-comparison-final2.jpg)关闭主要版面问题。一次 TextKit 尝试曾产生空白编辑区并被回退，最终图为可编辑版本。
3. [浮层旧图](qa-evidence/global-search-implementation.png)只有少量纯文字/通用图标且大面积空白；新版补 Logo、真实缩略图、标签、选中行和键盘提示，见[最终浅色对照](qa-evidence/global-search-comparison-final3.jpg)。源稿主题与数据仍不同，未将其说成深色像素级验收。
4. [旧设置对照](qa-evidence/settings-comparison.jpg)是独立 TabView，六组分散且通用页下半部空白，列为 P1/P2。改为主窗口两列六组后，[中间版](qa-evidence/settings-comparison-overview.jpg)解决架构；该中间版因第二测试实例导致热键冲突提示。最终在填充视觉库的单一 QA 实例中[重拍](qa-evidence/settings-comparison-final3.jpg)，六组同时可见，原 P1/P2 关闭。
5. [新建页初版](qa-evidence/create-comparison-prelim.jpg)主表单无卡片、右栏过窄、四模板分两行且无副说明、字段无计数，分别列为 P1/P2。改为双列卡片、右栏约 360 pt、三张右栏卡片、四模板单排及标题/标签计数后，[最终对照](qa-evidence/create-comparison-final3.jpg)关闭这些问题。
6. 编辑器与卡片随后放大 Inspector 标签胶囊、封面操作、页脚动作和资料库元数据；[资料库 final3](qa-evidence/library-comparison-final3.jpg)与[编辑器 final3](qa-evidence/editor-comparison-final3.jpg)实际打开后，旧 P2 字号/操作尺度问题关闭，但编辑器标题下仍是无底色标签文字，作为单独 P2 留到下一轮。
7. 菜单栏源稿与[初次同组件预览](qa-evidence/menu-comparison-component-final.jpg)并排：早期代码的通用图标、逐条打开按钮已改为真实封面、#标签、单一复制按钮和双底部按钮；两组缺“全部 >”列为 P2。[第二版](qa-evidence/menu-comparison-component-final2.jpg)补了两个可访问“全部”按钮，但固定 ScrollView 高度在最后一行后留出约 100 pt 空白；[第三版最终并排](qa-evidence/menu-comparison-component-final3.jpg)按实际行数收紧面板，标题入口和底部空白问题均关闭。该轮没有真实 status item 截图，不以组件预览宣称菜单栏交互通过。
8. 编辑器标题下复用浅底胶囊并补“+”后，[最终全图](qa-evidence/editor-comparison-final4.jpg)和[顶部局部](qa-evidence/editor-focused-final4.jpg)确认旧 P2 已关闭。CUA 点击“+”的 AX 树显示“输入标签”文本栏与“添加”按钮，入口可达；没有在测试库中提交新标签。

## Open Questions

- 真正的系统状态栏弹层及“全部”到主窗口的完整导航尚缺 GUI 证据；同组件预览只涵盖视觉与 AX 入口。
- 原生 macOS 控件与 PRD 静态概念图允许轻微色彩、边框和状态样式差异；精准字体型号和源稿点密度未知，不做伪精确的像素差百分比。

## Implementation Checklist

1. 在可访问状态栏的 macOS 环境实测真正弹层、两个“全部”的主窗口导航、关闭主窗后搜索复制，以及从别的前台应用触发 Option+Space 的方向键、Enter、Esc 和焦点归还。
2. 在交付 Bundle ID 应用上手动缩窗并核对外窗/内容区尺寸；继续实测 VoiceOver 与文字放大时主要控件是否可达。同源码临时小窗已覆盖 900 × 620 pt 内容区的主要布局。
3. 正式发行前在 macOS 14/15 完成安装与热键实机检查；当前只有 macOS 26.6 的视觉与构建证据。

## Follow-up Polish

- [P3] 浅色侧栏的原生灰比源稿淡蓝更中性；若后续有统一品牌材质 token，可轻调侧栏背景。
- [P3] 部分封面取景位置与源图不同；须先锁定同一图片原件和相同裁切规则再逐张精修。

**设计 QA 结论：** 已实拍并复核上述修正，当前没有可操作的 P0/P1/P2 视觉差异。900 × 620 pt 内容区在同源码临时构建中无主要布局碰撞；交付应用实际拖窗、真实菜单栏弹层、跨应用热键与旧系统实测仍是独立验收缺口。

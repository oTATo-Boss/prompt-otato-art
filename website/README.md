# oTATo prompt 本地网站预览

2026-10-04。采用用户确认的第二个方向修订图，以独立创作者的品牌作品为目标。背景和视觉主体由当前软件的真实界面延伸，保留品牌蓝 `#2B5FFC`、黑色、暖白、大字排版与实体电脑。

在软件项目根目录运行：

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
```

打开 http://127.0.0.1:4173/。沿用静态 HTML、CSS 和原生 JavaScript，无需安装网页依赖或构建软件。

正式官网为 `https://prompt.otato.art/`，所有章节保留在首页，没有 `/about` 等子页面。页内导航仅滚动到对应章节，不改变地址栏；带片段的旧入口会定位后恢复根地址。canonical 指向正式官网根地址。

## 页面与交互

- 黑色首屏：巨大 oTATo 字标与当前词库界面。
- 品牌蓝编辑章节：WORDS / IN / PLACE.，展示真实 Markdown 正文、封面、标签和保存位置。
- 暖白电脑章节：银色实体电脑内嵌用户指定的资料库截图。
- 黑色快速搜索章节：真实搜索浮层、默认 Option Space，以及标题／标签搜索和复制说明。
- CONTINUE. 收束：品牌文案、macOS 下载入口与系统支持说明。

每个章节在视口内停留，原生滚动控制窗口展开、文字错序入场、实体电脑镜头推进、搜索浮层弹出和结尾字母揭示。时间轴由 CSS sticky 与 requestAnimationFrame 实现，不接管滚轮；停止滚动后停止动画计算。章节导航和键盘焦点可直接到达可阅读的画面。

所有软件截图为纯展示；已移除使用指南、复制体验和截图放大的全部弹窗。顶部导航加入 GitHub 仓库链接，顶部右侧、首屏右侧与末屏蓝色按钮均为下载入口，统一指向 `https://github.com/susu177990-rgb/otato-prompt/releases/latest/download/oTATo-prompt.dmg`。正式包由签名公证流程发布，三个带 `data-download` 的链接会直接下载同一个最新 DMG。

导航、电脑章节和末屏明确说明「仅支持 macOS 14+」。

手机和较窄的平板竖屏采用上下构图，横向桌面保留错位双栏。高度不足 620px 时使用连续阅读和入场动效；系统减少动态效果偏好或页尾开关停用动效，并切回自然页面高度。切换模式时保留当前章节位置。

## 文件与素材

页面源文件为 `index.html`、`assets/site.css`、`assets/motion.css`、`assets/site.js`。

`product-library.webp` 来自用户指定的当前 Appshot；`product-editor.webp`、`product-quick-search.webp` 来自本次对运行中软件的真实截图。原图转换 WebP 后逐像素一致。首页通过 CSS 展示裁切和排版延伸。电脑外壳复用 `laptop.webp`，屏幕等比包含真实软件截图。`logo.svg` 沿用软件品牌资源。

字体与图标随站点本地加载。字体为 Noto Sans SC、Anton，图标为 Phosphor；许可证均在对应资源目录。

视觉目标见 `../docs/website-design-brief.md`，验证证据见 `design-qa.md`。本次交付为本地预览，发布事项见 `../docs/website-plan.md`。

## 正式部署

使用 `scripts/prepare_website.py --appcast <已发布清单>` 将公开文件和更新清单复制到 `.build/website`，再用 `packaging/website/wrangler.jsonc` 部署到 Cloudflare Workers Static Assets。该配置只绑定 `prompt.otato.art`。准备期可用 `--preview` 部署产品页面，此模式隐藏实际下载链接并显示「正式版准备中」。

安装与备份说明为 `help.html`，隐私说明为 `privacy.html`。完整发布状态与凭据要求见 `../docs/release-guide.md`。

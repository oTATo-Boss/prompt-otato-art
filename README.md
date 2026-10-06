<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="artwork/app-icon-line-white.svg">
  <img src="artwork/app-icon-line-black.svg" width="92" alt="oTATo prompt">
</picture>

# oTATo prompt

**免费的 macOS 本地提示词资料库**

在任何 App 里按 <kbd>⌥</kbd> <kbd>Space</kbd> 唤出，搜标题或标签，回车即复制。

[**↓ 下载 macOS 版**](https://prompt.otato.art/) · [使用说明](https://prompt.otato.art/help) · [更新日志](https://github.com/susu177990-rgb/otato-prompt/releases)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Universal](https://img.shields.io/badge/Universal-Apple%20Silicon%20%2B%20Intel-2B5FFC)
![免费](https://img.shields.io/badge/%E5%85%8D%E8%B4%B9-%E6%97%A0%E9%9C%80%E8%B4%A6%E5%8F%B7-2B5FFC)
[![下载量](https://img.shields.io/github/downloads/susu177990-rgb/otato-prompt/total?label=%E7%B4%AF%E8%AE%A1%E4%B8%8B%E8%BD%BD&color=2B5FFC)](https://github.com/susu177990-rgb/otato-prompt/releases)

</div>

<br>

[![观看 oTATo prompt 发布片](docs/assets/launch-poster.webp)](https://github.com/susu177990-rgb/otato-prompt/releases/download/v1.0-build9/otato-prompt-launch-1080p.mp4)

<div align="center"><sub><b><a href="https://github.com/susu177990-rgb/otato-prompt/releases/download/v1.0-build9/otato-prompt-launch-1080p.mp4">▶ 点击观看发布片</a></b> · 24 秒 · 1080p · 含声音</sub></div>

<br>

## 为什么做这个

写提示词的人都有同一个毛病：好不容易调出一条管用的，随手丢进备忘录、微信文件传输助手、飞书文档，或者存成 `prompt_最终版_v3.txt`。等真要用的时候，怎么都翻不出来。

oTATo prompt 把这些散落的好词收进一个地方——**只在你自己的 Mac 上**，不用注册，不联网同步，也不收费。

<br>

## 它能做什么

<table>
<tr>
<td width="50%" valign="top">

### ⌥ Space 随时唤出

不用切到 App。在 Midjourney、ComfyUI、浏览器、任何地方按下快捷键，浮层就在当前窗口上。

输入关键词 → <kbd>↑</kbd><kbd>↓</kbd> 选 → <kbd>Enter</kbd> 复制 → 粘贴。全程不离开手头的活。

菜单栏图标也能直接复制。

</td>
<td width="50%" valign="top">

### 每条好词都有位置

**文件夹**分门别类，支持多层嵌套；**标签**按使用频次自动排序，可多选；**封面**让卡片一眼认得出；**收藏**置顶常用的那几条。

「筛选」面板还能按包含／排除标签、收藏、有无封面、更新时间叠加组合。

</td>
</tr>
</table>

![资料库网格视图](docs/assets/library-grid.webp)

| | |
|---|---|
| **Markdown 正文** | 按常用 Markdown 排版编辑，保存、复制、导出都是原文，不会被改格式 |
| **批量导入** | 一次选多个 `.md` / `.txt`，或从 Finder 直接拖进来，文件名自动变标题 |
| **两种视图** | 网格看封面，列表左右分栏边看边改 |
| **备份与恢复** | 导出 `.otatoarchive` 完整归档，换机器直接恢复 |
| **更新提示** | 正式版会提示新版本，可在设置里关掉自动检查 |

> [!NOTE]
> 搜索**只匹配标题和标签，不搜正文**。资料库、菜单栏和全局浮层三处行为一致。

<br>

## 安装

当前公开版本 **1.0**，尚未经过 Apple 公证。

1. 从[官网](https://prompt.otato.art/)下载 ZIP 并解压，得到 `oTATo-prompt.dmg` 和「安装说明.pdf」。
2. 打开 DMG，把 **oTATo Prompt.app** 拖进「应用程序」。
3. 从「应用程序」启动。

> [!IMPORTANT]
> 因为没有公证，macOS 第一次会拦截。**先尝试启动一次**，再去「系统设置 → 隐私与安全性」点「仍要打开」。
> 只对从[官网](https://prompt.otato.art/)或本仓库 [Releases](https://github.com/susu177990-rgb/otato-prompt/releases/latest) 下载的包这么做。

首次启动资料库是空的，可以新建，或导入 UTF-8 编码的 `.md` / `.txt`。

**系统要求：** macOS 14 及以上 · Apple Silicon 与 Intel 均支持

<br>

## 功能细节

<details>
<summary><b>资料库、筛选与排序</b></summary>

<br>

选择父文件夹时，会汇总该文件夹及所有层级子文件夹的提示词。侧栏计数、标签筛选和右键菜单的「导出集合…」使用同一范围，排除废纸篓内容。新建和导入仍保存到当前选中的文件夹。

顶部标签按当前集合中的提示词数量从多到少排序，点击多选，再次点击取消。默认同时包含所选标签；「筛选」面板可切换为包含任一标签，并支持排除标签、收藏状态、封面、更新时间及有无标签。筛选立即生效，可搜索标签、逐项移除或清除全部；关键词搜索也能叠加这些条件。切换侧栏集合时清除筛选。

工具栏右侧的「⇅ 排序」只有「A～Z」和「修改时间」两项。名称按自然正序，修改时间固定从新到旧，新建也计为最新修改。顺序偏好保留到下次启动，新建和导入不会重置，收藏与取消收藏不改变排序，搜索结果同样使用所选顺序。

</details>

<details>
<summary><b>编辑与保存</b></summary>

<br>

列表视图为左侧文件夹、中间列表、右侧编辑器的三栏布局。列表封面在文字左侧，以 16:9 容器完整展示；右侧可直接改标题、文件夹、标签、正文、封面和收藏状态。

编辑后点右上角「保存」或按 <kbd>⌘</kbd><kbd>S</kbd>。网格的编辑页保存后返回资料库，列表编辑器保存后留在当前提示词；直接返回或切换提示词会放弃未保存的修改。设置通过应用菜单的「设置…」或 <kbd>⌘</kbd><kbd>,</kbd> 打开独立窗口。

</details>

<details>
<summary><b>导入</b></summary>

<br>

资料库右上角的「导入」可一次选择一个或多个 `.md` / `.txt`，也可从 Finder 把多个文件拖进资料库。标题使用文件名（去扩展名），正文保持原样；在某个文件夹中导入时会保存到该文件夹。批量读取在后台完成，全部成功后一次保存，导入后自动显示新卡片。

</details>

<details>
<summary><b>外观与主题</b></summary>

<br>

「设置 → 外观 → 高亮配色」可切换「黑白反色」「备忘录黄」和「oTATo 蓝」，默认黑白反色。App 图标使用透明底的黑、白两套 Logo 线稿，由 macOS 根据**系统图标外观**选择；Finder 和 Dock 的圆角底板由系统绘制。

悬停使用半透明主题色，侧栏、列表和有效筛选使用实色选中态；网格卡片选中时显示 3 点宽的主题色圆角边框，保留封面和文字区原色。视图切换图标使用主题原色，深色模式下也不变浅。

</details>

<details>
<summary><b>数据位置与性能</b></summary>

<br>

提示词正文、封面和应用内备份位于 macOS 沙盒的 Application Support 目录。开发运行和安装到「应用程序」使用同一个 Bundle ID（`art.otato.prompt`），继续加载现有资料库。请用「设置 → 数据」导出 `.otatoarchive` 备份；恢复归档会替换当前资料库，并先自动备份原库。

启动时先显示预载进度，建立搜索索引、预热有内存上限的封面缓存，并完成首屏布局后显示资料库。网格使用原生滚动容器和复用卡片，保持自适应列数。关闭主窗口会隐藏并保留窗口、滚动位置及缓存，点击 Dock 图标或从菜单栏打开时恢复；完全退出（<kbd>⌘</kbd><kbd>Q</kbd>）后下次启动重新预载。系统内存紧张时允许回收缓存。

全局搜索浮层默认展示收藏，可在「设置 → 快捷键」切换为空搜索时展示最近使用。若看不到菜单栏图标，检查「设置 → 通用 → 菜单栏显示」是否开启。

</details>

<br>

## 开发

Xcode 工程 `oTATo Prompt.xcodeproj`，28 个 Swift 文件，最低系统 macOS 14，Bundle ID `art.otato.prompt`。打开后选 **oTATo Prompt** scheme 运行到 **My Mac**。

<details>
<summary><b>命令行构建 Universal 测试版</b></summary>

<br>

```sh
xcodebuild -project 'oTATo Prompt.xcodeproj' \
  -scheme 'oTATo Prompt' -configuration Release \
  -destination 'generic/platform=macOS' \
  ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' \
  SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG \
  ENABLE_DEBUG_DYLIB=NO ENABLE_HARDENED_RUNTIME=NO \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual build
```

工程通过 Swift Package Manager 固定使用 Sparkle 2.10。测试版不启用公开自动更新；正式更新清单地址为 `https://prompt.otato.art/updates/appcast.xml`。

</details>

<details>
<summary><b>SwiftUI 画布预览</b></summary>

<br>

调整新建页布局时打开 `PromptCreateView.swift`，用 **Editor → Canvas** 显示画布，首次点 **Resume** 启动预览。画布随源码变化自动刷新，可在深色和浅色紧凑预览间切换并直接输入。预览使用内存资料库，「创建」和「返回」仅用于展示，不写入实际提示词。

完整应用的保存、搜索、复制、菜单栏和全局快捷键用 <kbd>⌘</kbd><kbd>R</kbd> 运行检查。

</details>

<details>
<summary><b>打包品牌 DMG 安装界面</b></summary>

<br>

背景资源与 Finder 布局在 `packaging/dmg/`。在仓库根目录用 [dmgbuild](https://dmgbuild.readthedocs.io/en/latest/settings.html) 打包已构建的 App：

```sh
python3 -m venv .build/dmg-env
.build/dmg-env/bin/pip install -r packaging/dmg/requirements.txt
swift packaging/dmg/render-background.swift
sips -z 512 768 packaging/dmg/background@2x.png --out packaging/dmg/background.png
.build/dmg-env/bin/dmgbuild -s packaging/dmg/settings.py \
  -D 'app=/tmp/otato-release-derived/Build/Products/Release/oTATo Prompt.app' \
  'oTATo prompt 安装' \
  'dist/oTATo-prompt-1.0-build5-test-20261004-universal.dmg'
```

换 App 路径、版本和日期即可沿用该界面。DMG 使用 oTATo 蓝与提示词卡片背景，左侧 App、右侧「应用程序」入口，图标可直接拖动安装；背景含普通与 Retina 两种分辨率。插画由 imagegen 按已确认的预览制作，白色线条 Logo 使用 App 的原始透明 PNG 等比合成。

</details>

<br>

## 发行

发行包由 GitHub Actions 自动构建并发布到 Releases 与官网，标签格式 `v<版本>-build<构建号>`；`dist/` 不纳入源码仓库。官网入口直接指向最新 ZIP，内含 DMG 和独立的安装说明 PDF；应用内更新继续使用签名 DMG。

当前为**已公开发行的未公证版本**：启用更新器的 Release 构建、ad hoc 代码签名与 EdDSA 更新包签名。核心数据流程已通过 macOS 14、15、26 的云端检查，包括跨进程重开和完整归档恢复——这不含真实窗口、快捷键或签名升级验收。已修复 macOS 14 恢复带标签归档时的崩溃。

未公证发行路径不要求 Apple 开发者会员；自动部署需要 Cloudflare API Token（已配置）。日后可切换到 Developer ID 签名公证发行。

完整配置、验收状态与真实安装升级记录见[发行指南](docs/release-guide.md)。

<br>

---

<div align="center">
<sub>独立制作 · <a href="https://prompt.otato.art/">prompt.otato.art</a> · <a href="https://prompt.otato.art/privacy">隐私</a></sub>
</div>

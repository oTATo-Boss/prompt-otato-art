# oTATo prompt

免费的 macOS 本地提示词资料库。按 ⌥ Space 随时唤出，搜索标题或标签，回车即复制。

![oTATo prompt 资料库](website/assets/product-library.webp)

**[下载 macOS 版](https://prompt.otato.art/)** · [GitHub Releases](https://github.com/susu177990-rgb/otato-prompt/releases/latest) · [安装与使用说明](https://prompt.otato.art/help)

- 免费，无需账号；提示词和封面只保存在本机。
- ⌥ Space 全局快速搜索，回车复制；也可从菜单栏复制。
- 网格与列表视图，文件夹、标签、封面、收藏及多条件筛选。
- Markdown 正文；批量导入 `.md` / `.txt`；完整资料库备份与恢复。
- 正式版提供版本更新提示，可在设置中关闭自动检查。
- 支持 macOS 14 及以上，包含 Apple Silicon 与 Intel 架构。

## 安装

当前公开版本为 1.0，尚未经过 Apple 公证。最新构建以 [Releases](https://github.com/susu177990-rgb/otato-prompt/releases/latest) 为准。

1. 从[官网](https://prompt.otato.art/)下载 ZIP 并解压，得到 `oTATo-prompt.dmg` 和「安装说明.pdf」。
2. 打开 DMG，将 **oTATo Prompt.app** 拖到“应用程序”。
3. 从“应用程序”启动。若 macOS 因未公证而阻止打开，先尝试启动一次，再到“系统设置 → 隐私与安全性”选择“仍要打开”。只对从官网或本仓库 Releases 下载的安装包执行此操作。
4. 首次启动的资料库为空。可新建 Prompt，或从应用内导入 UTF-8 编码的 `.md` / `.txt` 文件。

## 工程信息

- Xcode 工程：`oTATo Prompt.xcodeproj`。最低系统版本为 macOS 14，Bundle ID 为 `art.otato.prompt`。
- 发行包由 GitHub Actions 自动构建并发布到 Releases 与官网，标签格式为 `v<版本>-build<构建号>`；`dist/` 不纳入源码仓库。

## 功能说明

DMG 使用 oTATo 蓝与可爱的提示词卡片背景，左侧为 App，右侧为“应用程序”入口。图标可直接拖动安装；背景包含普通与 Retina 两种分辨率。

在“设置 → 外观 → 高亮配色”中可切换“黑白反色”、“备忘录黄”和“oTATo 蓝”；默认使用黑白反色。App 图标使用透明底的黑、白两套 Logo 线稿，由 macOS 根据**系统图标外观**选择；Finder 和 Dock 的圆角底板由系统绘制。`dist/` 仅保留最新测试 DMG。

悬停使用半透明主题色，侧栏、列表和有效筛选使用实色选中态；网格卡片选中时显示 3 点宽的主题色圆角边框，保留封面和文字区原色。视图切换图标使用主题原色，深色模式下也不变浅。

正文直接按常用 Markdown 排版编辑，保存、复制和导出均使用 Markdown 原文；导入的 `.txt` 也按同一方式管理。全局搜索浮层默认展示收藏，可在“设置 → 快捷键”切换为空搜索时展示最近使用。若看不到菜单栏图标，请检查“设置 → 通用 → 菜单栏显示”已开启。

资料库、菜单栏和全局浮层的搜索只匹配标题与标签，不搜索正文。

资料库右上角的“导入”按钮可一次选择一个或多个 `.md` / `.txt` 文件，也可从 Finder 将多个文件拖到资料库。标题使用文件名（去掉扩展名），正文保持原样；在某个文件夹中导入时会保存到该文件夹。批量读取在后台完成，全部文件读取成功后一次保存，导入后自动显示新卡片。

选择父文件夹时，会汇总该文件夹及所有层级子文件夹的提示词；侧栏计数、标签筛选和文件夹右键菜单中的“导出集合…”使用同一范围，排除废纸篓中的内容。新建和导入仍保存到当前选中的文件夹。

顶部标签按当前集合中的提示词数量从多到少排序，可点击多选，再次点击取消。默认同时包含所选标签；“筛选”面板可切换为包含任一标签，并支持排除标签、收藏状态、封面、更新时间及有无标签。筛选立即生效，可搜索标签、逐项移除条件或清除全部；关键词搜索也可叠加这些条件。切换侧栏集合时清除筛选。

顶部工具栏左侧为网格／列表切换和搜索，右侧导入按钮前的“⇅ 排序”菜单只有“A～Z”和“修改时间”两项。名称按自然正序排列，修改时间固定从新到旧，新建提示词也计为最新修改。顺序偏好会保留到下次启动，新建和导入不会重置；收藏和取消收藏不会改变排序。搜索结果也使用所选顺序。

列表视图采用左侧文件夹、中间提示词列表、右侧编辑器的布局。列表封面位于文字左侧，以 16:9 容器完整展示图片；右侧可直接修改标题、文件夹、标签、正文、封面及收藏状态。

编辑提示词后，点击右上角“保存”或按 ⌘S 保存。网格的编辑页保存后返回资料库，列表编辑器保存后留在当前提示词；直接返回或切换提示词会放弃未保存的修改。设置通过应用菜单的“设置…”或 ⌘, 打开独立窗口。

启动时先显示预载进度，建立搜索索引、预热有内存上限的封面缓存，并完成首屏布局后显示资料库。网格使用原生滚动容器和复用卡片，保持自适应列数。关闭主窗口会隐藏并保留窗口、滚动位置及缓存，点击 Dock 图标或从菜单栏打开时恢复；完全退出（⌘Q）后，下次启动重新预载。系统内存紧张时允许回收缓存。

提示词正文、封面和应用内备份位于 macOS 沙盒的 Application Support 目录。开发运行和安装到“应用程序”使用同一个 Bundle ID，继续加载现有资料库。请使用“设置 → 数据”导出 `.otatoarchive` 备份；恢复归档会替换当前资料库，并先自动备份原库。

## 本地构建

需要 Xcode 和 macOS SDK。打开工程后选择 **oTATo Prompt** scheme，运行到 **My Mac**。

调整新建页布局时，打开 `PromptCreateView.swift`，使用 **Editor → Canvas** 显示画布，首次点击 **Resume** 启动预览。画布会随源码变化自动刷新，可在深色和浅色紧凑预览之间切换并直接输入。预览使用内存资料库；“创建”和“返回”按钮仅用于展示，不写入实际提示词。

完整应用的保存、搜索、复制、菜单栏和全局快捷键用 **⌘R** 运行检查；再次运行会加载最新代码。

命令行构建 Universal 测试版：

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

### 制作品牌安装界面

背景资源与 Finder 布局保存在 `packaging/dmg/`。在仓库根目录使用 [dmgbuild](https://dmgbuild.readthedocs.io/en/latest/settings.html) 打包已构建的 App：

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

更换 App 路径、版本和日期即可沿用该安装界面。插画由 imagegen 按已确认的预览制作，白色线条 Logo 使用 App 的原始透明 PNG 等比合成；原生 App 图标及应用程序文件夹由 Finder 展示。

## 发行状态

已公开发行未公证版本：使用启用更新器的 Release 构建、ad hoc 代码签名与 EdDSA 更新包签名，官网下载 ZIP 内提供与 DMG 并列的「安装说明.pdf」。

核心数据流程已通过 macOS 14、15、26 的云端检查，包括跨进程重开和完整归档恢复；这不包含真实窗口、快捷键或签名升级验收。已修复 macOS 14 恢复带标签归档时的崩溃。真实安装与升级验收记录见[发行指南](docs/release-guide.md)。

## 正式发行流程

官网与软件的发布配置均在本项目内维护。最新版本以 GitHub Releases 的最新标签为准；官网入口直接指向最新 ZIP，内含 DMG 和独立的安装说明 PDF；应用内更新继续使用签名 DMG。正式版默认每小时检查新版本并显示安装提示，可在设置中关闭；开发构建不会启动更新器。

完整配置与验收状态见 [发行指南](docs/release-guide.md)。未公证发行路径不要求 Apple 开发者会员；自动部署需要 Cloudflare API Token（已配置）。日后可以切换到 Developer ID 签名公证发行。

# oTATo prompt

oTATo prompt 是简体中文 macOS 提示词资料库。提示词和封面保存在本机，使用时无需账号；主窗口、菜单栏和全局搜索浮层可查找并复制提示词。

## 当前交付

- Xcode 工程：`oTATo Prompt.xcodeproj`。最低系统版本为 macOS 14，Bundle ID 为 `art.otato.prompt`。
- 最新本地测试磁盘映像：`dist/oTATo-prompt-1.0-test-create-header-universal.dmg`，包含 Apple Silicon 与 Intel 两种架构。该目录不纳入源码仓库。
- 测试版以临时签名制作，尚未经过 Developer ID 签名和 Apple 公证。它用于本地验收，不是正式发行版。

## 安装和试用测试版

以下步骤适用于本地交付的测试包；GitHub 源码仓库不包含该 DMG。

1. 打开 `dist/` 中的测试 DMG，将 **oTATo Prompt.app** 拖到“应用程序”。
2. 从“应用程序”启动。若 macOS 因未公证而阻止打开，先尝试启动一次，再到“系统设置 → 隐私与安全性”选择“仍要打开”。只对确认来自本工程的测试产物执行此操作。
3. 首次启动的资料库为空。可新建 Prompt，或从应用内导入 UTF-8 编码的 `.md` / `.txt` 文件。

在“设置 → 外观 → 高亮配色”中可切换“黑白反色”和“备忘录黄”；默认使用黑白反色。App 图标使用透明底的黑、白两套 Logo 线稿，由 macOS 根据**系统图标外观**选择；Finder 和 Dock 的圆角底板由系统绘制。原测试 DMG 保留在 `dist/` 中，方便对比。

正文直接按常用 Markdown 排版编辑，保存、复制和导出均使用 Markdown 原文；导入的 `.txt` 也按同一方式管理。全局搜索浮层默认展示收藏，可在“设置 → 快捷键”切换为空搜索时展示最近使用。若看不到菜单栏图标，请检查“设置 → 通用 → 菜单栏显示”已开启。

资料库右上角的“导入”按钮可一次选择一个或多个 `.md` / `.txt` 文件，也可从 Finder 将多个文件拖到资料库。标题使用文件名（去掉扩展名），正文保持原样；在某个文件夹中导入时会保存到该文件夹。批量读取在后台完成，全部文件读取成功后一次保存，导入后自动显示新卡片。

选择父文件夹时，会汇总该文件夹及所有层级子文件夹的提示词；侧栏计数、标签筛选和“导出当前集合”使用同一范围，排除废纸篓中的内容。新建和导入仍保存到当前选中的文件夹。

顶部标签按当前集合中的提示词数量从多到少排序，可点击多选，再次点击取消。默认同时包含所选标签；“筛选”面板可切换为包含任一标签，并支持排除标签、收藏状态、封面、更新时间及有无标签。筛选立即生效，可搜索标签、逐项移除条件或清除全部；关键词搜索也可叠加这些条件。“导出当前集合”导出当前筛选结果，切换侧栏集合时清除筛选。

“筛选”旁的显示顺序菜单支持按编辑时间、使用时间、创建时间或名称排序，并可切换方向；选择“手动排序”后，可拖动卡片或列表项调整位置。顺序偏好会保留到下次启动，新建和导入不会重置；收藏和取消收藏不改变编辑时间或手动位置。搜索结果按相关度排列。

提示词正文、封面和应用内备份位于 macOS 沙盒的 Application Support 目录。请使用应用内“数据管理”导出 `.otatoarchive` 备份；恢复归档会替换当前资料库，并先自动备份原库。

## 本地构建

需要 Xcode 和 macOS SDK。打开工程后选择 **oTATo Prompt** scheme，运行到 **My Mac**。

调整新建页布局时，打开 `PromptCreateView.swift`，使用 **Editor → Canvas** 显示画布，首次点击 **Resume** 启动预览。画布会随源码变化自动刷新，可在深色和浅色紧凑预览之间切换并直接输入。预览使用内存资料库；“创建”和“返回”按钮仅用于展示，不写入实际提示词。

完整应用的保存、搜索、复制、菜单栏和全局快捷键用 **⌘R** 运行检查；再次运行会加载最新代码。

命令行构建 Universal 测试版：

```sh
xcodebuild -project 'oTATo Prompt.xcodeproj' \
  -scheme 'oTATo Prompt' -configuration Debug \
  -destination 'generic/platform=macOS' \
  ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual build
```

工程通过 Swift Package Manager 固定使用 Sparkle 2.10。测试版不启用公开自动更新；更新清单地址已预留为 `https://otato.art/updates/appcast.xml`。

## 正式发布前

当前机器只验证了 macOS 26.6。正式发行还需在 macOS 14/15 实机检查安装、快捷键和窗口行为，使用 Developer ID 签名并公证 DMG，签署 Sparkle 安装包，上传固定版本的 GitHub Release，再发布 appcast 并从旧版本实测升级。在完成这些步骤前，请勿将测试 DMG 作为正式版本分发。

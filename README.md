# oTATo prompt

oTATo prompt 是简体中文 macOS 提示词资料库。提示词和封面保存在本机，使用时无需账号；主窗口、菜单栏和全局搜索浮层可查找并复制提示词。

## 当前交付

- Xcode 工程：`oTATo Prompt.xcodeproj`。最低系统版本为 macOS 14，Bundle ID 为 `art.otato.prompt`。
- 本地测试磁盘映像：`dist/` 目录中的 Universal DMG，包含 Apple Silicon 与 Intel 两种架构。该目录不纳入源码仓库。
- 测试版以临时签名制作，尚未经过 Developer ID 签名和 Apple 公证。它用于本地验收，不是正式发行版。

## 安装和试用测试版

以下步骤适用于本地交付的测试包；GitHub 源码仓库不包含该 DMG。

1. 打开 `dist/` 中的测试 DMG，将 **oTATo Prompt.app** 拖到“应用程序”。
2. 从“应用程序”启动。若 macOS 因未公证而阻止打开，先尝试启动一次，再到“系统设置 → 隐私与安全性”选择“仍要打开”。只对确认来自本工程的测试产物执行此操作。
3. 首次启动的资料库为空。可新建 Prompt，或从应用内导入 UTF-8 编码的 `.md` / `.txt` 文件。

提示词正文、封面和应用内备份位于 macOS 沙盒的 Application Support 目录。请使用应用内“数据管理”导出 `.otatoarchive` 备份；恢复归档会替换当前资料库，并先自动备份原库。

## 本地构建

需要 Xcode 和 macOS SDK。打开工程后选择 **oTATo Prompt** scheme，运行到 **My Mac**。命令行构建 Universal 测试版：

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

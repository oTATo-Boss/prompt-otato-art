# oTATo prompt 官网准备与发布边界

更新于 2026-10-04。用户已确认第二个方向修订图，并授权将真实软件界面延伸为网站视觉，本地交互预览位于 `website/`，运行地址 http://127.0.0.1:4173/。视觉与交互以 `website-design-brief.md` 和网页实际效果为准；这份文档保留产品事实与后续发布事项。

## 当前范围

- 目标官网域名 `https://prompt.otato.art`，网页代码放在本软件项目的独立目录，沿用静态 HTML、CSS 和少量原生 JavaScript。
- 当前词库采用用户指定的 Appshot，编辑页和搜索浮层来自本次运行中软件的真实截图；不使用早期 QA 截图。
- 软件免费；不推导为开源或永久免费。页面呈现完整产品体验，不使用等待发布作为核心叙事。
- 已制作本地视觉与交互预览；未修改软件源码、提交、推送、上传、部署或修改 DNS。
- 未读取、复用或修改旧的独立 `otato.art` 项目。正式发布阶段将 Sparkle 地址统一到 `https://prompt.otato.art/updates/appcast.xml`。

## 已核实的产品事实

软件 README、Xcode 配置及当前 DMG 内 App 元数据一致：1.0（build 5），最低 macOS 14.0，包含 arm64 与 x86_64。当前测试包 `dist/oTATo-prompt-1.0-build5-test-20261004-universal.dmg` 为 ad hoc 签名，无 TeamIdentifier；尚未完成 Developer ID 签名和 Apple 公证。双架构包装不等于 Intel 实机兼容性已验证。

功能包含资料库网格／列表、Markdown 编辑、文件夹、标签、收藏、多条件筛选、导入导出、菜单栏复制、默认 Option Space 全局搜索，以及完整资料库备份恢复。搜索匹配标题与标签；正文编辑后需保存或按 Cmd S。

不宣传变量模板、AI 生成、iCloud 同步、正文全文搜索或自动保存。提示词和封面存储在本机，使用无需账号；应用包含 Sparkle 和联网权限，不写「绝不联网」。

## 后续发布事项

按用户最新要求，顶部右侧、首屏右侧和末屏蓝色按钮已统一直达最新正式安装包：`https://github.com/susu177990-rgb/otato-prompt/releases/latest/download/oTATo-prompt.dmg`；顶部另有用户指定的 GitHub 仓库入口。Releases 目前没有发布包，这些入口为后续正式发布准备，未连接本地测试 DMG。网站明确标注仅支持 macOS 14+。

上线前需要落实正式签名、公证、最低支持系统与架构的兼容性验收，确认截图与封面的公开使用范围，补充真实反馈渠道，并依据实际网站、下载和更新服务完善隐私说明。

完整资料库备份入口为设置 → 数据 → 完整资料库 → 备份与恢复，格式为 `.otatoarchive`；恢复会替换当前库，并自动备份原库。`.md`／`.txt` 文本交换不能替代完整资料库备份。

下载入口现预留 GitHub Releases；网站托管和 DNS 仍待后续决定。仅在用户授权相应发布操作后执行；当前任务停留在可审阅的本地预览。

## 正式发布阶段（2026-10-04）

用户现已授权官网上线、正式包和自动更新。Cloudflare 为已确认的 DNS 与托管平台。初期产品页用准备模式明确标注正式下载未开放，待 Apple Developer Program、Developer ID 与公证凭据到位后，由正式发布工作流启用真实下载和更新清单。此阶段维护均在本软件项目内完成。

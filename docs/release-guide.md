# oTATo prompt 官网发行

官网：`https://prompt.otato.art/`。更新清单：`https://prompt.otato.art/updates/appcast.xml`。
通过官网发行，不上架 Mac App Store。

## 当前发行方式

2026-10-05：用户确认暂时无法加入 Apple Developer Program，接受先准备**未公证发行版**。官网下载包将明确注明未公证；首次安装先解压官网 ZIP，再按与 DMG 同目录的「安装说明.pdf」执行系统的「仍要打开」步骤。

未公证路径显式使用 `--distribution unnotarized`。它构建无 `DEBUG` 的 Universal Release，保留 App Sandbox，逐层为 Sparkle 组件和 App 做 ad hoc 签名，再为完整 DMG 生成 EdDSA 更新签名。主程序与 Sparkle 组件不启用 Hardened Runtime，以支持没有 Developer ID 的加载方式。发行记录明确注明没有 Apple 公证。

Developer ID 路径保留为 `--distribution developer-id`，且是命令行默认值。它要求有效证书、Hardened Runtime、App 与 DMG 公证及票据验证，任何失败均停止，不会因证书缺失而自动切换发行方式。

## 发行与验证记录

已公开发布 1.0（build 6）。核心数据逻辑已经通过 macOS 14、15、26 的云端检查：[检查记录](https://github.com/susu177990-rgb/otato-prompt/actions/runs/37215265212)。覆盖保存、跨进程重开、中文与 Markdown 保留、标签与嵌套文件夹、封面、批量导入回滚、唯一文件名导出、废纸篓及完整备份恢复。检查中已修复 macOS 14 恢复带标签归档时的崩溃，v1 模型保持不变。

已生成 1.0（build 6）的未公证 Universal Release DMG，验证了 ad hoc 代码签名、完整包 EdDSA 更新签名、DMG 完整性与 SHA-256。挂载后确认包含 App、应用程序入口和「安装说明.pdf」，PDF 与打包源文件一致，嵌入中文字体且已检查排版。这是旧版布局；自 2026-10-06 起，安装说明放在官网下载 ZIP 中，与 DMG 并列，DMG 内只保留 App 和应用程序入口。

已在独立沙盒资料库验证实际升级：自动检查回调发现 build 6（非手动触发），下载、EdDSA 校验、替换并重启成功；随后用生产界面手动检查 build 7，显示更新说明，通过包含教程的 DMG 完成安装并重启。两次升级均保留正文、中文与 Unicode、标签、收藏、文件夹及封面字节；生产界面可见保留的记录。测试 App 安装在 `/Applications`，使用独立 Bundle ID，不访问用户正式资料库。旧版官网三个按钮已启用并指向最新 DMG，浏览器实际下载、公开完整包 SHA-256 及线上签名更新清单一致性检查通过。

发布配置已合并至 `main`。软件改动推送或合并到 `main` 会触发自动发布。

## 自动发布配置

仓库：`susu177990-rgb/otato-prompt`。

仓库 Actions variable **`RELEASE_DISTRIBUTION`** 当前已设为 `unnotarized`；可选择 `unnotarized` 或 `developer-id`；未设置时使用 `developer-id`。

两种方式都需要：

| Secret | 内容 |
| --- | --- |
| `SPARKLE_PRIVATE_KEY` | 与 App 公钥匹配的 Ed25519 私钥种子；已保存 |
| `CLOUDFLARE_API_TOKEN` | 当前账户 Workers Scripts 编辑、otato.art 的 Workers Routes 编辑及区域只读；已保存，CI 部署已通过 |

只有 `developer-id` 方式额外需要 `DEVELOPER_ID_P12`、`DEVELOPER_ID_P12_PASSWORD`、`APPLE_ID`、`APPLE_APP_PASSWORD`、`APPLE_TEAM_ID`。这些凭据暂未配置，等开发者会员生效后再补齐。

Secrets 通过 GitHub Secrets 页面或 `gh secret set` 的标准输入写入，不能粘贴到普通聊天或提交 Git。本机 Wrangler OAuth 可做本机部署，不能替代 CI 所需的持久 Token。本机 Sparkle 私钥位于 Keychain 的 `art.otato.prompt` 账户中；生成签名时通过标准输入传递，临时导出在受限目录读取后立即删除。

## 手动制作未公证发行包

提交源码并确认工作区干净，再执行：

```sh
python3 -m venv .build/release-env
.build/release-env/bin/pip install -r packaging/dmg/requirements.txt
.build/release-env/bin/python scripts/release.py build \
  --distribution unnotarized \
  --version 1.0 --build 6 --tag v1.0-build6 --notes docs/release-notes.md
```

产物为 `dist/releases/v1.0-build6/` 中的 ZIP、DMG、签名更新清单与 SHA-256 发行记录。官网下载 ZIP 包含 `oTATo-prompt.dmg` 和「安装说明.pdf」两个并列文件，解压后即可先阅读教程。DMG 只包含 App 和应用程序入口。PDF 已预生成并保存在 `packaging/dmg/安装说明.pdf`；重新生成使用 `scripts/build_install_guide.py --font <Noto Sans SC 静态 TTF>`，需要 reportlab。

## 自动发布行为

- 软件改动推送到 `main`，或手动运行 Publish macOS release workflow。
- 先在 macOS 14、15、26 的 runner 检查核心数据流程，再构建所选发行方式。
- 从现有发行标签和 Xcode 配置分配递增 build；对外版本号来自 `MARKETING_VERSION`。
- GitHub Release 标签为 `v<version>-build<build>`，DMG 固定名 `oTATo-prompt.dmg`。官网下载 ZIP 固定名 `oTATo-prompt.zip`，按钮直达 `releases/latest/download/oTATo-prompt.zip`。
- Sparkle appcast 的下载链接指向固定版本 DMG，签名覆盖整个安装包。自动检查默认每小时一次，由用户选择安装，开发构建不启动更新器。
- 官网与 appcast 同步部署到 Cloudflare；仅网站变更会保留最新发行清单。未公证发行说明明确标注安装步骤。
- 公开验证会检查三个 ZIP 下载按钮、ZIP 内的独立 PDF、线上清单，以及 ZIP 和更新 DMG 的完整字节与 SHA-256。网站单独部署在首次 ZIP 发布前保留旧站，避免提前放出不存在的下载链接。

## 首次发行验收

1. 从官网实际下载 ZIP，解压后先阅读 PDF，再打开 DMG；确认 DMG 内没有 PDF，App 能拖入应用程序。
2. 用系统的「仍要打开」允许首次运行，不关闭全局 Gatekeeper。
3. 在可用的 Mac 上验证窗口、设置、菜单栏、快捷键和复制；macOS 14/15 的云端数据检查不等于其 GUI 验收。
4. 从旧的启用更新器的构建实测升级，验证提示、签名、安装替换、重启、数据和封面保留。
5. 官网、日志、更新清单和实际 DMG 的版本及字节一致。

仅完成编译或生成签名，不能声称以上真实安装和升级已经通过。

## 日后补充 Developer ID

注册 [Apple Developer Program](https://developer.apple.com/programs/enroll/)，在 Xcode Settings → Accounts 创建或导入 Developer ID Application 证书及私钥。只有 `.cer` 没有私钥不能签名。[Apple 证书说明](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)。

配置 Apple 的 CI secrets，将 `RELEASE_DISTRIBUTION` 切换为 `developer-id`。保留 Bundle ID、Sparkle 公钥和资料库模型，实测从未公证版本升级后再发行公证版本。

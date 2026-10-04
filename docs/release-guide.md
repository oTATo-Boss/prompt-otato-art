# oTATo prompt 正式发布

官网：`https://prompt.otato.art/`。更新清单：`https://prompt.otato.art/updates/appcast.xml`。
面向官网下载发行，使用 Developer ID；不走 Mac App Store。

官网产品页已于 2026-10-04 部署至 Cloudflare，线上已检查三个下载入口均为「正式版准备中」，没有将测试包作为正式版分发。正式 appcast 将在首个公证版本发布时部署。

## 目前的实际状态

2026-10-04：源码候选版本为 1.0（build 6）。已完成 Universal Release 编译检查，但该检查关闭了代码签名，产物不能作为正式下载发布。最新的现有测试 DMG 仍是 build 5。

真实数据代码已通过隔离资料库检查：跨进程保存和重开、中文与 Markdown 原文保留、旧 TXT 记录、标签与嵌套文件夹、封面保留、无效 UTF-8 批量导入回滚、重名文本导出、废纸篓恢复、完整归档、损坏归档拒绝、恢复前安全备份、恢复后再次重开。命令为 `python3 scripts/check_data.py`。这些检查不接触用户默认资料库，不等于真实系统快捷键、菜单栏交互或签名升级已经验收。

`release.yml` 准备在 main 分支的软件改动提交后构建、签名、公证、发布安装包，并部署官网和更新清单。这个流程仍待真实证书和公证凭据的完整执行验证。首个正式安装包、从旧正式版升级及新版本通知尚未验收。

## 先办理 Apple Developer Program

用户确认尚未加入付费开发者计划。注册入口：[Apple Developer Program](https://developer.apple.com/programs/enroll/)。独立开发者可以按个人身份注册，需要开启双重认证并使用真实姓名。官方年费为 99 美元；实际支付使用当地币种和页面价格。加入开发者计划不要求上架 App Store。

会员生效后，在本机 Xcode 的 Settings → Accounts 加入 Apple Account，然后创建或导入 **Developer ID Application** 证书及其私钥。[Apple 的证书说明](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)。只下载一个 `.cer` 而没有对应私钥不能签名。

验证命令：

```sh
security find-identity -v -p codesigning
python3 scripts/release.py preflight
```

需要出现有效的 Developer ID Application 身份。Bundle ID 保持 `art.otato.prompt`，v1 数据模型保持不变。

## 自动发布凭据

GitHub 仓库为 `susu177990-rgb/otato-prompt`。Actions 已保存 `SPARKLE_PRIVATE_KEY`；它与 Info.plist 公钥匹配。本机 Sparkle 私钥位于 Keychain 的 `art.otato.prompt` 账户中，不将其提交到仓库。

首次正式发布前仍需在该仓库的 Actions secrets 中配置：

| Secret | 内容 |
| --- | --- |
| `DEVELOPER_ID_P12` | Developer ID Application 证书和私钥的 `.p12` 导出，Base64 编码 |
| `DEVELOPER_ID_P12_PASSWORD` | 该导出文件的密码 |
| `APPLE_ID` | 已加入开发者计划的 Apple Account |
| `APPLE_APP_PASSWORD` | 用于公证的应用专用密码 |
| `APPLE_TEAM_ID` | 开发者团队 ID |
| `CLOUDFLARE_API_TOKEN` | 对当前账户的 Workers Scripts、Workers Routes 及相应域名配置有权限的持久 API Token |

凭据通过 GitHub 的 Secrets 页面或 `gh secret set` 的标准输入写入，不能粘贴到普通聊天、写进脚本或提交 Git。本机 Wrangler OAuth 登录可用于本机部署，但不能替代 CI 所需的持久 API Token。

## 发布行为

- 将经过验证的软件代码合并并推送到 `main`，或手动运行 Signed macOS release workflow。
- 发布前在 macOS 14、15、26 的 GitHub runner 上执行真实数据逻辑检查。实际窗口、跨应用快捷键和菜单栏仍需要相应系统的 GUI 验收。
- `scripts/release.py next-build` 从现有发布标签和 Xcode 配置分配递增构建号。对外版本号来自 Xcode 的 `MARKETING_VERSION`。新版本可修改此值，如 `1.0.1`。
- 构建流程使用 Release、Universal、Hardened Runtime，无 `DEBUG` 覆盖。App 和 DMG 均通过 Developer ID 签名、Apple 公证与票据验证。任何一步失败都停止发布。
- GitHub Release 使用固定标签 `v<version>-build<build>`，其 DMG 文件统一命名为 `oTATo-prompt.dmg`。官网三个下载按钮直达 `releases/latest/download/oTATo-prompt.dmg`，不再跳到列表页。
- 更新清单由 Sparkle 工具生成，安装包具有 EdDSA 签名，链接指向固定版本的安装包。自动检查默认每小时一次，由用户确认安装；开发构建不连接正式更新源。
- 网站与更新清单一起部署到 Cloudflare。仅网站改动会保留最新公开 Release 的 appcast，避免清单回退或丢失。
- 公开验证脚本检查三个下载按钮、线上清单和实际下载的完整 DMG SHA-256。尚未执行的检查不能记为通过。

## 手动制作正式包

先将当前发布源码提交并确认工作区干净，在已安装有效 Developer ID 身份的 Mac 上执行：

```sh
python3 -m venv .build/release-env
.build/release-env/bin/pip install -r packaging/dmg/requirements.txt
xcrun notarytool store-credentials OTATO_NOTARY
.build/release-env/bin/python scripts/release.py build \
  --version 1.0 --build 6 --tag v1.0-build6 --notes docs/release-notes.md
```

`notarytool store-credentials` 用交互方式录入公证凭据。多份签名身份存在时，给构建命令补上 `--identity` 选择正确证书。正式发布不会退回临时签名或跳过公证。

## 首次发布的验收门槛

1. 从官网实际下载 DMG，确认正常拖入应用程序并启动。
2. 在 macOS 14/15 与对应架构上验证真实窗口、菜单栏、跨应用 Option Space、复制、Enter/Esc 和焦点归还。
3. 对旧测试包的真实资料库先导出归档，再验证安装正式版后数据保留。
4. 用一份旧的已签名公证构建实测升级，确认下载签名校验、替换、重启、资料库保留和新版本通知。
5. 官网、下载、版本日志和更新清单的版本一致，公开下载字节与签名验收过的包一致。

以上门槛未全部通过前，不能将目标标记为完成。

# 官网累计下载

末屏下载按钮下的统计由 `/api/downloads` 提供。Worker 逐页读取 GitHub Releases，汇总所有非草稿版本中 `oTATo-prompt.dmg` 与 `oTATo-prompt.zip` 的 `download_count`，不统计更新清单、发行记录或源代码归档。

这是下载次数，包含更新、重复下载和发布验证；不是独立用户数。保留历史 Release 后，新版本发布会自动加入累计总数。

有效数据每 15 分钟重新获取，浏览器缓存 5 分钟。短暂的上游错误可以回退到一天内的最近有效统计，页面注明“最近统计”；没有有效数据时显示暂时不可用，不以 0 或部分版本的计数代替。前端首次请求失败会自动重试一次。

无需 GitHub 凭据或额外数据库。静态页面继续由 Assets 服务，只有统计路径优先进入 Worker。源码与网站共同发布，因此后续软件发行部署同样保留该接口。

验证：`node --test packaging/website/worker.test.mjs`。本地静态 HTTP 服务不提供接口，联调需先运行网站准备脚本，再使用 `wrangler dev --config packaging/website/wrangler.jsonc`。

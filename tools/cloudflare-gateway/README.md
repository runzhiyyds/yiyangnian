# 颐养年独立业务入口

入口：`https://yiyangnian-api.pet-food-advisor.asia`。仅绑定这个精确子域名；Worker 名称为 `yiyangnian-api`，固定转发至原项目 `https://jhntjagskjklbrsgturh.supabase.co`。与高佳欣的 Worker、上游项目和会话键独立，不修改根域名或其他产品路由。

用户授权沿用已经验证的方案修复本项目后，业务代码已部署到自己的 Cloudflare 账户。密码登录、客户端公开密钥、用户 JWT 与业务请求先经 HTTPS 到达 Worker，再经 HTTPS 转至原 Supabase。没有服务端密钥、凭据日志或缓存，鉴权及 RLS 仍由 Supabase 处理。

`GET /health` 不转发凭据，仅访问原项目的 Auth health；上游 401 是没有 API Key 的预期响应，代表路径可达，不等于业务鉴权通过。

本地检查：

```bash
cd /Users/guochenyuan/Desktop/颐养年/tools/cloudflare-gateway
npm test
npx --yes wrangler@4.149.0 deploy --dry-run
```

17 项测试覆盖固定上游、凭据传递、禁用标记、路径与 Auth admin 限制、写入不重试、10 秒响应期限、晚到响应取消、分页、RPC、重定向、模拟 WebSocket 与 Storage 字节。当前 APP 未使用 Supabase Storage 或 Realtime 产品功能，模拟覆盖不代表那些业务已经上线回归。

`wrangler.jsonc` 是业务配置，`wrangler.readonly.jsonc` 保留只读检测回退配置。首次部署使用 Scripts API 上传打包模块，再以 Domains API 的 `zone_name` 绑定新子域名。OAuth 的 `workers_scripts:write` 已允许这些接口；Wrangler 自动配置 custom domain 还可能涉及区域读取权限，权限不足不能通过覆盖根域名或修改现有产品 DNS 来规避。

参考：[模块上传 API](https://developers.cloudflare.com/api/resources/workers/subresources/scripts/methods/update/)、[独立域名配置](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)。

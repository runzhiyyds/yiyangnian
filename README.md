# 颐养年店铺管理

Flutter Android 客户端，业务后端为腾讯 CloudBase 上海 PostgreSQL。项目业务代码在 `app/`，数据库文档与迁移在 `docs/`。

客户端使用 CloudBase 身份认证与 PostgreSQL HTTP API，不再经由 Cloudflare 转发访问 Supabase。Supabase 仍作为切换期的历史数据源，正式发布前需要完成最终增量对账。数据库基线、RLS 和导入说明见 [CloudBase PostgreSQL 迁移](docs/cloudbase_migrations/README.md)。

本地配置使用 `app/env.json`，示例为 `app/env.json.example`。`CLOUDBASE_ENV_ID` 是客户端可公开的环境标识；不得向客户端配置腾讯云 SecretId、SecretKey 或任何服务端密钥。统一调试入口会先生成编译配置：

```bash
cd /Users/guochenyuan/Desktop/颐养年/app
./scripts/run_with_env.sh android
```

客户端保留 Supabase SDK 作为业务查询构造器，但网络兼容层会将请求转换为 CloudBase 的认证与 PostgREST 接口。这不代表运行时仍会访问 Supabase。

## 数据一致性与缓存

- 读请求最多复用 30 秒、按登录账号隔离；同一查询的并发请求会合并，避免页面重复加载。
- 写入成功后会立即清理相关缓存并通知页面刷新；切换账号或退出时全量清理，不会跨账号共用数据。
- 网络层只对可安全重放的读请求做有界重试，不会自动重放新增、修改、撤销等写请求。
- 新增业务记录通过 `client_request_id` 与数据库唯一索引实现幂等；发布客户端前必须先执行 `docs/cloudbase_migrations/005_write_idempotency.sql`。
- 当前没有开启长连实时订阅。同一手机内成功写入后立即刷新；控制台直接改库等外部变更，需要手动刷新或等待短缓存过期才可见。

# 颐养年店铺管理

Flutter Android 客户端，业务后端为 Supabase。项目业务代码在 `app/`，数据库文档与迁移在 `docs/`。

移动网络业务入口已接入 `https://yiyangnian-api.pet-food-advisor.asia`，固定转发至原 Supabase 项目。原账号会话、数据与权限规则保持在原项目中；见 [移动网络接入与验证记录](docs/移动网络修复-2026-10-13.md)。

本地配置使用 `app/env.json`，示例为 `app/env.json.example`，只填写原项目客户端公开密钥，不能填写服务端密钥。统一调试入口会先生成编译配置：

```bash
cd /Users/guochenyuan/Desktop/颐养年/app
./scripts/run_with_env.sh android
```

网络入口与回退配置见 [业务入口说明](tools/cloudflare-gateway/README.md)。此次网络接入不需要执行数据库迁移；生产迁移须另外遵守既有备份、执行顺序与验收要求。

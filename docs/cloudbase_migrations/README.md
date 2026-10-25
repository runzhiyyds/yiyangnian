# CloudBase PostgreSQL 迁移

此目录只用于腾讯 CloudBase PostgreSQL 新环境，不要在 Supabase 线上库执行。

执行顺序：

1. 在确认 `public` Schema 没有颐养年业务表后，完整执行 `001_cloudbase_baseline.sql`。
2. 执行 `002_verify_baseline.sql`。五项结果应依次证明：9 张业务表、9 张表启用 RLS、9 个 `owner_id` 为 `text`、9 条账号隔离策略、3 个库存审计触发器。
3. 使用临时账号通过 CloudBase HTTP API 调用 `initialize_current_account`，验证默认大项、REST 权限和 RLS。
4. 验收通过后再生成并执行历史数据导入脚本。不要直接向新库导入旧 Supabase 的 `owner_id UUID`。

设计边界：

- CloudBase 的 `auth.uid()` 返回 JWT `sub`，类型是 `text`。
- 业务表不外键引用 CloudBase 系统表 `auth.users`，也不在该表安装业务触发器。
- 默认大项由已认证用户显式调用 `initialize_current_account()` 幂等创建。
- `anon` 没有业务表权限；`authenticated` 仍受每张表的 RLS 限制。
- 001 是全新环境基线，不是可重复执行的增量迁移；检测到任一目标表已存在时会主动停止。

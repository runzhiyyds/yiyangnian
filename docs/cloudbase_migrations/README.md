# CloudBase PostgreSQL 迁移

此目录只用于腾讯 CloudBase PostgreSQL 新环境，不要在 Supabase 线上库执行。

执行顺序：

1. 在确认 `public` Schema 没有颐养年业务表后，完整执行 `001_cloudbase_baseline.sql`。
2. 如果 001 在 `003_harden_rpc_security.sql` 加入仓库之前已经执行，再执行 003；新环境直接执行最新版 001 时不需要重复执行 003。
3. 执行 `002_verify_baseline.sql`。五项结果应依次证明：9 张业务表、9 张表启用 RLS、9 个 `owner_id` 为 `text`、9 条账号隔离策略、3 个库存审计触发器。
4. 使用临时账号通过 CloudBase HTTP API 调用 `initialize_current_account`，验证默认大项、REST 权限和 RLS。
5. 验收通过后再生成并执行历史数据导入脚本。不要直接向新库导入旧 Supabase 的 `owner_id UUID`。

## 全量 CSV 导入

生产 CSV 和生成的全量 SQL 均被 `.gitignore` 排除，严禁提交到 GitHub。使用：

```bash
python3 tools/generate_cloudbase_import.py \
  --source-dir docs/颐养年备份 \
  --output docs/cloudbase_migrations/generated/004_import_full_snapshot.sql \
  --old-production-owner '<旧正式账号 UUID>' \
  --old-demo-owner '<旧体验账号 UUID>' \
  --new-production-owner '<CloudBase 正式账号 sub>' \
  --new-demo-owner '<CloudBase 体验账号 sub>'
```

生成器不接收密码或 Token。生成结果包含真实客户数据，只能保存在本机并通过 CloudBase SQL 编辑器执行。脚本会检查目标业务表为空、两个目标账号存在、默认大项完整；所有导入和校验处于同一事务，失败会整体回滚。

设计边界：

- CloudBase 的 `auth.uid()` 返回 JWT `sub`，类型是 `text`。
- 业务表不外键引用 CloudBase 系统表 `auth.users`，也不在该表安装业务触发器。
- 默认大项由已认证用户显式调用 `initialize_current_account()` 幂等创建。
- `anon` 没有业务表权限；`authenticated` 仍受每张表的 RLS 限制。
- 普通 RPC 使用 `SECURITY INVOKER` 继承表权限和 RLS；必须跨账号重绑设备 Token 的函数显式校验 `authenticated` 角色。
- 001 是全新环境基线，不是可重复执行的增量迁移；检测到任一目标表已存在时会主动停止。

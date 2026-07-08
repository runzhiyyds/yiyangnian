# 颐养年 - Supabase 删库重建（选新加坡区域）

可以删掉旧项目、新建一个，**区域选 Singapore (ap-southeast-1)**，与高佳欣一致，避免国内解析失败。

## 步骤

### 1. 新建项目

1. 打开 [Supabase Dashboard](https://supabase.com/dashboard)
2. **New project**
3. **Region 选：Singapore (ap-southeast-1)**（不要选 Mumbai）
4. 填好名称、数据库密码，创建

### 2. 执行建表与 RLS

1. 进入新项目 → 左侧 **SQL Editor**
2. **New query**，把本仓库里的  
   `docs/supabase_重建新项目_一键执行.sql`  
   整份复制进去，点 **Run**
3. 确认无报错（表、序列、函数、RLS 都会建好）

### 3. 创建登录账号

1. 左侧 **Authentication** → **Users**
2. **Add user** → **Create new user**
3. Email：`18613544351@163.com`  
   Password：`123456`  
   （与 APP 里默认账号一致）
4. 创建后该用户即可用来登录 APP

### 4. 拿到新项目的 URL 和 Key

1. 左侧 **Settings**（齿轮）→ **API**
2. 记下：
   - **Project URL**（如 `https://xxxxx.supabase.co`）
   - **anon public**（Project API keys 里 anon 那一串）

### 5. 改本地配置并重新打包

1. 编辑 `app/env.json`，改成新项目的：
   ```json
   {
     "SUPABASE_URL": "https://你的新项目ref.supabase.co",
     "SUPABASE_ANON_KEY": "你的新项目anon key"
   }
   ```
2. 在项目根目录执行：
   ```bash
   ./publish_new_version.sh 1.0.7 "切换 Supabase 至新加坡区域"
   ```

### 6. 旧项目（可选）

- 确认新项目、新包都正常后，再到 Supabase 里 **Delete project** 删掉旧的孟买项目即可。
- 旧项目里的数据不会自动迁到新项目；若需要，只能手动导出/导入或重新录入。

---

**一键 SQL 文件**：`docs/supabase_重建新项目_一键执行.sql`（已包含表、序列、函数、RLS，按上面顺序执行一次即可）。

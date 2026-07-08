-- 关闭「邮箱确认」后的补救：将已有账号全部标记为已确认
-- 若登录仍提示 Email not confirmed，在 SQL Editor 执行本文件
--
-- 同时请在 Supabase Dashboard 关闭邮箱确认（否则新用户仍会未确认）：
--   Authentication → Providers → Email → 关闭 Confirm email → Save

UPDATE auth.users
SET email_confirmed_at = NOW(), updated_at = NOW()
WHERE email_confirmed_at IS NULL;

UPDATE auth.identities
SET
  identity_data = jsonb_set(
    COALESCE(identity_data, '{}'::jsonb),
    '{email_verified}',
    'true'::jsonb,
    true
  ),
  updated_at = NOW()
WHERE provider = 'email'
  AND COALESCE(identity_data->>'email_verified', 'false') <> 'true';

-- 体验账号密码重置（可选）
CREATE EXTENSION IF NOT EXISTS pgcrypto;

UPDATE auth.users
SET encrypted_password = crypt('123456', gen_salt('bf')), updated_at = NOW()
WHERE email = 'user@example.com';

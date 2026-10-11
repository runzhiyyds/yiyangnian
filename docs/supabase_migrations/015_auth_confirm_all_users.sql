-- 历史文件名保留兼容；当前脚本只修复固定体验账号，不再批量修改全部用户。
-- 正式账号及其他 Auth 用户不会被确认、改密或更新。

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '2min';

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_demo_id UUID := 'd4e5f6a7-b8c9-4012-d345-e67890123456';
  v_demo_email TEXT := 'user@example.com';
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM auth.users
    WHERE id = v_demo_id
      AND LOWER(email) = LOWER(v_demo_email)
  ) THEN
    RAISE EXCEPTION '015 已停止：固定体验账号不存在或 UUID、邮箱不匹配';
  END IF;

  UPDATE auth.users
  SET
    email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
    encrypted_password = crypt('123456', gen_salt('bf')),
    updated_at = NOW()
  WHERE id = v_demo_id
    AND LOWER(email) = LOWER(v_demo_email);

  UPDATE auth.identities
  SET
    identity_data = JSONB_SET(
      COALESCE(identity_data, '{}'::JSONB),
      '{email_verified}',
      'true'::JSONB,
      TRUE
    ),
    updated_at = NOW()
  WHERE user_id = v_demo_id
    AND provider = 'email';

  IF NOT FOUND THEN
    RAISE EXCEPTION '015 已停止：体验账号缺少 email identity';
  END IF;

  RAISE NOTICE '只修复了固定体验账号，未修改其他 Auth 用户';
END $$;

COMMIT;

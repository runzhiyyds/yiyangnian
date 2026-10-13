-- 历史文件名保留兼容；当前脚本只按邮箱修复体验账号，不再批量修改全部用户。
-- 正式账号及其他 Auth 用户不会被确认、改密或更新。

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '2min';

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_demo_id UUID;
  v_demo_email TEXT := 'user@example.com';
  v_email_match_count INTEGER;
BEGIN
  SELECT COUNT(*)
  INTO v_email_match_count
  FROM auth.users
  WHERE LOWER(email) = LOWER(v_demo_email);

  IF v_email_match_count <> 1 THEN
    RAISE EXCEPTION '015 已停止：体验邮箱必须且只能对应一个 Auth 用户，当前数量：%', v_email_match_count;
  END IF;

  SELECT id
  INTO v_demo_id
  FROM auth.users
  WHERE LOWER(email) = LOWER(v_demo_email);

  UPDATE auth.users
  SET
    email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
    encrypted_password = crypt('123456', gen_salt('bf')),
    updated_at = NOW()
  WHERE id = v_demo_id;

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

  RAISE NOTICE '只修复了体验账号 %，未修改其他 Auth 用户', v_demo_id;
END $$;

COMMIT;

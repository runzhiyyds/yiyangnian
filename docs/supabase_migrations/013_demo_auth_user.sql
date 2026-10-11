-- 体验账号：user@example.com / 123456
--
-- 生产安全边界：
-- 1. 只创建固定的体验账号，不修改任何其他用户。
-- 2. 若同邮箱或固定 UUID 已被其他账号占用，立即报错并整体回滚。
-- 3. 若体验账号已存在，不重置密码、不改确认状态；密码维护请使用 Supabase Dashboard。
-- 4. 不再批量确认项目中的其他用户。

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '2min';

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_demo_id UUID := 'd4e5f6a7-b8c9-4012-d345-e67890123456';
  v_demo_email TEXT := 'user@example.com';
  v_user_by_id auth.users%ROWTYPE;
  v_user_by_email auth.users%ROWTYPE;
BEGIN
  SELECT *
  INTO v_user_by_id
  FROM auth.users
  WHERE id = v_demo_id;

  SELECT *
  INTO v_user_by_email
  FROM auth.users
  WHERE LOWER(email) = LOWER(v_demo_email);

  IF v_user_by_id.id IS NOT NULL
    AND LOWER(COALESCE(v_user_by_id.email, '')) <> LOWER(v_demo_email) THEN
    RAISE EXCEPTION '013 已停止：体验账号固定 UUID 已被其他邮箱占用';
  END IF;

  IF v_user_by_email.id IS NOT NULL
    AND v_user_by_email.id <> v_demo_id THEN
    RAISE EXCEPTION '013 已停止：体验账号邮箱已绑定到其他 UUID：%', v_user_by_email.id;
  END IF;

  IF v_user_by_id.id IS NOT NULL THEN
    IF v_user_by_id.email_confirmed_at IS NULL THEN
      RAISE EXCEPTION '013 已停止：体验账号已存在但邮箱未确认，请手动确认或执行已加固的 015';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM auth.identities
      WHERE user_id = v_demo_id
        AND provider = 'email'
    ) THEN
      RAISE EXCEPTION '013 已停止：体验账号存在但缺少 email identity，请在 Authentication 用户页修复';
    END IF;

    RAISE NOTICE '体验账号已存在且状态有效，未修改密码或确认状态';
    RETURN;
  END IF;

  INSERT INTO auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_super_admin,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) VALUES (
    v_demo_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    v_demo_email,
    crypt('123456', gen_salt('bf')),
    NOW(),
    '{"provider":"email","providers":["email"]}'::JSONB,
    '{"display_name":"体验账号"}'::JSONB,
    NOW(),
    NOW(),
    FALSE,
    '',
    '',
    '',
    ''
  );

  INSERT INTO auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES (
    v_demo_id,
    v_demo_id,
    v_demo_email,
    JSONB_BUILD_OBJECT(
      'sub', v_demo_id::TEXT,
      'email', v_demo_email,
      'email_verified', TRUE,
      'phone_verified', FALSE
    ),
    'email',
    NOW(),
    NOW(),
    NOW()
  );

  RAISE NOTICE '体验账号已创建；未修改其他 Auth 用户';
END $$;

COMMIT;

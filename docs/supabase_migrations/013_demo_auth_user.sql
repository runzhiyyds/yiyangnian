-- 体验账号：user@example.com / 123456
-- 在 Supabase SQL Editor 中执行
--
-- 【必做】关闭邮箱确认（项目无发信能力时）：
--   Dashboard → Authentication → Providers → Email
--   关闭「Confirm email / 确认电子邮件」→ Save
--
-- 本脚本会：创建体验账号；若已存在则补全「已确认」状态并重置密码为 123456

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_user_id uuid := 'd4e5f6a7-b8c9-4012-d345-e67890123456';
  v_existing_id uuid;
BEGIN
  SELECT id INTO v_existing_id FROM auth.users WHERE email = 'user@example.com';

  IF v_existing_id IS NOT NULL THEN
    UPDATE auth.users
    SET
      email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
      encrypted_password = crypt('123456', gen_salt('bf')),
      updated_at = NOW()
    WHERE id = v_existing_id;

    UPDATE auth.identities
    SET
      identity_data = jsonb_set(
        COALESCE(identity_data, '{}'::jsonb),
        '{email_verified}',
        'true'::jsonb,
        true
      ),
      updated_at = NOW()
    WHERE user_id = v_existing_id AND provider = 'email';

    RAISE NOTICE '体验账号已存在，已标记为邮箱已确认并重置密码为 123456';
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
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'user@example.com',
    crypt('123456', gen_salt('bf')),
    NOW(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"体验账号"}'::jsonb,
    NOW(),
    NOW(),
    false,
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
    v_user_id,
    v_user_id,
    'user@example.com',
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', 'user@example.com',
      'email_verified', true,
      'phone_verified', false
    ),
    'email',
    NOW(),
    NOW(),
    NOW()
  );

  RAISE NOTICE '体验账号已创建：user@example.com / 123456（邮箱已确认，可直接登录）';
END $$;

-- 将项目中所有未确认用户标记为已确认（小团队内部账号，无自助注册）
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

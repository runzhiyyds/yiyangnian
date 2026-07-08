-- ============================================================
-- Supabase Cron 配置：定时调用 push_notifier Edge Function
-- ============================================================
-- 使用前请先在 Supabase Dashboard 中启用 pg_cron 和 pg_net 扩展
-- Database → Extensions → 搜索并启用 pg_cron、pg_net
-- ============================================================

-- 1. 将 project_url 和 anon_key 存入 Vault（仅首次执行，若已存在会报 duplicate key 错误，可跳过）
-- 将 YOUR_PROJECT_REF 替换为你的项目 ref（如 xyzabc123）
-- 将 YOUR_ANON_KEY 替换为你的 Supabase anon/public key
-- SELECT vault.create_secret(
--   'https://YOUR_PROJECT_REF.supabase.co',
--   'project_url'
-- );
-- SELECT vault.create_secret(
--   'YOUR_ANON_KEY',
--   'anon_key'
-- );

-- 2. 每天 09:00（北京时间）发送生日周报推送（Vault 已配置时执行以下部分）
SELECT cron.schedule(
  'push-birthday-weekly',
  '0 1 * * *',  -- UTC 01:00 = 北京时间 09:00
  $$
  SELECT net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/push_notifier',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'anon_key')
    ),
    body := '{"type":"birthday_weekly"}'::jsonb
  ) AS request_id;
  $$
);

-- 3. 每天 22:00（北京时间）发送经营日报推送
SELECT cron.schedule(
  'push-daily-report',
  '0 14 * * *',  -- UTC 14:00 = 北京时间 22:00
  $$
  SELECT net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/push_notifier',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'anon_key')
    ),
    body := '{"type":"daily_report"}'::jsonb
  ) AS request_id;
  $$
);

-- ============================================================
-- 时区说明
-- ============================================================
-- pg_cron 默认使用 UTC。中国 UTC+8：
-- - 北京时间 09:00 → cron '0 1 * * *'  （UTC 01:00）
-- - 北京时间 22:00 → cron '0 14 * * *' （UTC 14:00）
-- 若项目已设置数据库时区为 Asia/Shanghai，可按本地时间理解。
-- ============================================================

-- 查看已创建的 cron 任务
-- SELECT * FROM cron.job;

-- 删除任务（如需）
-- SELECT cron.unschedule('push-birthday-weekly');
-- SELECT cron.unschedule('push-daily-report');

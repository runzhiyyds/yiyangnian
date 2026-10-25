-- 颐养年 - 写入幂等键
-- 目标：网络响应丢失后，同一个客户端保存动作重试时不会生成重复记录。
-- 该迁移只增加可空字段和唯一索引，不改写任何历史行。

BEGIN;

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'storage_records',
    'consumption_records',
    'inventory_purchase_records',
    'inventory_supplementary_in_records',
    'inventory_consumption_records'
  ]
  LOOP
    IF to_regclass('public.' || table_name) IS NULL THEN
      RAISE EXCEPTION '005 已停止：缺少业务表 public.%', table_name;
    END IF;
  END LOOP;
END $$;

ALTER TABLE storage_records
  ADD COLUMN IF NOT EXISTS client_request_id text;
ALTER TABLE consumption_records
  ADD COLUMN IF NOT EXISTS client_request_id text;
ALTER TABLE inventory_purchase_records
  ADD COLUMN IF NOT EXISTS client_request_id text;
ALTER TABLE inventory_supplementary_in_records
  ADD COLUMN IF NOT EXISTS client_request_id text;
ALTER TABLE inventory_consumption_records
  ADD COLUMN IF NOT EXISTS client_request_id text;

CREATE UNIQUE INDEX IF NOT EXISTS storage_records_owner_request_key
  ON storage_records(owner_id, client_request_id);
CREATE UNIQUE INDEX IF NOT EXISTS consumption_records_owner_request_key
  ON consumption_records(owner_id, client_request_id);
CREATE UNIQUE INDEX IF NOT EXISTS inventory_purchase_owner_request_key
  ON inventory_purchase_records(owner_id, client_request_id);
CREATE UNIQUE INDEX IF NOT EXISTS inventory_supp_in_owner_request_key
  ON inventory_supplementary_in_records(owner_id, client_request_id);
CREATE UNIQUE INDEX IF NOT EXISTS inventory_consumption_owner_request_key
  ON inventory_consumption_records(owner_id, client_request_id);

COMMIT;

SELECT
  count(*) FILTER (WHERE column_name = 'client_request_id') AS idempotency_columns
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
    'storage_records',
    'consumption_records',
    'inventory_purchase_records',
    'inventory_supplementary_in_records',
    'inventory_consumption_records'
  );

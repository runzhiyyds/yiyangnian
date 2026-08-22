-- 账号级数据隔离迁移
--
-- 业务规则：APP 只有一个门店，但每个登录账号只能访问自己的业务数据。
-- 安全规则：本脚本不会猜测现有正式数据归属。执行前必须把下面的全 0 UUID
-- 替换为现有正式数据所属账号的 auth.users.id，否则事务会主动失败。

BEGIN;

CREATE TEMP TABLE account_isolation_context (
  production_owner UUID NOT NULL,
  demo_owner UUID NOT NULL
) ON COMMIT DROP;

INSERT INTO account_isolation_context (production_owner, demo_owner) VALUES (
  '00000000-0000-0000-0000-000000000000'::UUID,
  'd4e5f6a7-b8c9-4012-d345-e67890123456'::UUID
);

DO $$
DECLARE
  v_production_owner UUID;
  v_demo_owner UUID;
  v_has_demo_data BOOLEAN;
BEGIN
  SELECT production_owner, demo_owner
  INTO v_production_owner, v_demo_owner
  FROM account_isolation_context;

  IF v_production_owner = '00000000-0000-0000-0000-000000000000'::UUID THEN
    RAISE EXCEPTION '请先填写 production_owner，再执行账号隔离迁移';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_production_owner) THEN
    RAISE EXCEPTION 'production_owner 不存在于 auth.users：%', v_production_owner;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM customers WHERE name LIKE '演示-%'
    UNION ALL
    SELECT 1 FROM storage_small_item_options WHERE name LIKE '演示-%'
  ) INTO v_has_demo_data;

  IF v_has_demo_data AND
      NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_demo_owner) THEN
    RAISE EXCEPTION '检测到演示数据，但体验账号 UUID 不存在：%', v_demo_owner;
  END IF;
END $$;

-- 先保留演示小项对应的大项名称，稍后为体验账号复制独立选项。
CREATE TEMP TABLE demo_small_big_mapping ON COMMIT DROP AS
SELECT small_item.id AS small_item_id, big_item.name AS big_item_name
FROM storage_small_item_options AS small_item
LEFT JOIN storage_big_item_options AS big_item
  ON big_item.id = small_item.storage_big_item_id
WHERE small_item.name LIKE '演示-%';

ALTER TABLE customers ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);
ALTER TABLE storage_big_item_options ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);
ALTER TABLE storage_small_item_options ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);
ALTER TABLE storage_records ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);
ALTER TABLE consumption_records ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);
ALTER TABLE inventory_purchase_records ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);
ALTER TABLE inventory_consumption_records ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);
ALTER TABLE inventory_supplementary_in_records ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);

-- 推送 Token 也属于账号数据。旧 Token 不猜测归属，先停用，登录后由 APP 重建绑定。
CREATE TABLE IF NOT EXISTS push_devices (
  id BIGSERIAL PRIMARY KEY,
  device_token TEXT UNIQUE NOT NULL,
  platform TEXT NOT NULL DEFAULT 'android',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE push_devices
  ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);
UPDATE push_devices SET is_active = FALSE WHERE owner_id IS NULL;

CREATE OR REPLACE FUNCTION claim_push_device(
  p_device_token TEXT,
  p_platform TEXT DEFAULT 'android'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '未登录，无法绑定推送设备';
  END IF;

  UPDATE push_devices
  SET owner_id = auth.uid(), platform = p_platform, is_active = TRUE
  WHERE device_token = p_device_token;

  IF NOT FOUND THEN
    BEGIN
      INSERT INTO push_devices (owner_id, device_token, platform, is_active)
      VALUES (auth.uid(), p_device_token, p_platform, TRUE);
    EXCEPTION WHEN unique_violation THEN
      UPDATE push_devices
      SET owner_id = auth.uid(), platform = p_platform, is_active = TRUE
      WHERE device_token = p_device_token;
    END;
  END IF;
END $$;

REVOKE ALL ON FUNCTION claim_push_device(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION claim_push_device(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION release_push_device(p_device_token TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE push_devices
  SET is_active = FALSE
  WHERE device_token = p_device_token AND owner_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION release_push_device(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION release_push_device(TEXT) TO authenticated;

-- 现有数据归属：演示标记数据归体验账号，其余数据归显式指定的正式账号。
UPDATE customers AS row
SET owner_id = CASE
  WHEN row.name LIKE '演示-%' THEN context.demo_owner
  ELSE context.production_owner
END
FROM account_isolation_context AS context
WHERE row.owner_id IS NULL;

UPDATE storage_big_item_options AS row
SET owner_id = context.production_owner
FROM account_isolation_context AS context
WHERE row.owner_id IS NULL;

UPDATE storage_small_item_options AS row
SET owner_id = CASE
  WHEN row.name LIKE '演示-%' THEN context.demo_owner
  ELSE context.production_owner
END
FROM account_isolation_context AS context
WHERE row.owner_id IS NULL;

UPDATE storage_records AS row
SET owner_id = CASE
  WHEN row.customer_name LIKE '演示-%'
    THEN context.demo_owner
  ELSE context.production_owner
END
FROM account_isolation_context AS context
WHERE row.owner_id IS NULL;

UPDATE consumption_records AS row
SET owner_id = COALESCE(
  (SELECT parent.owner_id FROM storage_records AS parent
   WHERE parent.id = row.storage_record_id),
  context.production_owner
)
FROM account_isolation_context AS context
WHERE row.owner_id IS NULL;

UPDATE inventory_purchase_records AS row
SET owner_id = CASE
  -- 编号序列是全局共享的，正式进货也可能是 JH90xxx。只有进货单的
  -- 全部小项都属于体验账号时，才将整单归入演示数据。
  WHEN CARDINALITY(COALESCE(row.storage_small_item_ids, ARRAY[]::INT[])) > 0
   AND CARDINALITY(COALESCE(row.storage_small_item_ids, ARRAY[]::INT[])) = (
     SELECT COUNT(*)
     FROM unnest(COALESCE(row.storage_small_item_ids, ARRAY[]::INT[])) AS ids(item_id)
     JOIN storage_small_item_options AS item
       ON item.id = ids.item_id
      AND item.owner_id = context.demo_owner
   )
    THEN context.demo_owner
  ELSE context.production_owner
END
FROM account_isolation_context AS context
WHERE row.owner_id IS NULL;

UPDATE inventory_supplementary_in_records AS row
SET owner_id = COALESCE(
  (SELECT item.owner_id FROM storage_small_item_options AS item
   WHERE item.id = row.storage_small_item_id),
  context.production_owner
)
FROM account_isolation_context AS context
WHERE row.owner_id IS NULL;

UPDATE inventory_consumption_records AS row
SET owner_id = COALESCE(
  (SELECT parent.owner_id FROM storage_records AS parent
   WHERE parent.id = row.source_storage_record_id),
  (SELECT item.owner_id FROM storage_small_item_options AS item
   WHERE item.id = row.storage_small_item_id),
  context.production_owner
)
FROM account_isolation_context AS context
WHERE row.owner_id IS NULL;

-- 先把大项名称唯一约束改为账号内唯一，才能为不同账号复制同名默认项。
ALTER TABLE storage_big_item_options
  DROP CONSTRAINT IF EXISTS storage_big_item_options_name_key;
ALTER TABLE storage_big_item_options
  ADD CONSTRAINT storage_big_item_options_owner_name_key UNIQUE (owner_id, name);

-- 每个账号拥有自己的大项选项；不共享同一行。
INSERT INTO storage_big_item_options (owner_id, name)
SELECT user_row.id, default_name.name
FROM auth.users AS user_row
CROSS JOIN (
  VALUES ('藏红方'), ('御至宝'), ('元气植'), ('颐养年'), ('未来生物')
) AS default_name(name)
ON CONFLICT DO NOTHING;

-- 体验小项改为引用体验账号自己的大项副本。
UPDATE storage_small_item_options AS small_item
SET storage_big_item_id = demo_big.id
FROM demo_small_big_mapping AS mapping
JOIN account_isolation_context AS context ON TRUE
JOIN storage_big_item_options AS demo_big
  ON demo_big.owner_id = context.demo_owner
 AND demo_big.name = mapping.big_item_name
WHERE small_item.id = mapping.small_item_id;

-- 数组字段无法使用普通外键，迁移前先校验历史数据；发现异常则整个事务回滚。
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM inventory_purchase_records
    WHERE CARDINALITY(COALESCE(storage_small_item_ids, ARRAY[]::INT[])) = 0
       OR CARDINALITY(COALESCE(storage_big_items, ARRAY[]::TEXT[])) <>
          CARDINALITY(COALESCE(storage_small_item_ids, ARRAY[]::INT[]))
       OR CARDINALITY(COALESCE(storage_small_item_ids, ARRAY[]::INT[])) <>
          CARDINALITY(COALESCE(quantities, ARRAY[]::INT[]))
  ) THEN
    RAISE EXCEPTION '存在大项、小项、数量未对齐的进货单，请先修复再迁移';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM storage_records AS parent
    CROSS JOIN LATERAL unnest(
      COALESCE(parent.storage_small_item_ids, ARRAY[]::INT[])
    ) AS ids(item_id)
    LEFT JOIN storage_small_item_options AS item
      ON item.id = ids.item_id AND item.owner_id = parent.owner_id
    WHERE item.id IS NULL
  ) THEN
    RAISE EXCEPTION '存在引用了其他账号小项的储值记录';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM inventory_purchase_records AS parent
    CROSS JOIN LATERAL unnest(
      COALESCE(parent.storage_small_item_ids, ARRAY[]::INT[])
    ) AS ids(item_id)
    LEFT JOIN storage_small_item_options AS item
      ON item.id = ids.item_id AND item.owner_id = parent.owner_id
    WHERE item.id IS NULL
  ) THEN
    RAISE EXCEPTION '存在引用了其他账号小项的进货记录';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM consumption_records AS parent
    CROSS JOIN LATERAL unnest(
      COALESCE(parent.consumption_project_ids, ARRAY[]::INT[])
    ) AS ids(item_id)
    LEFT JOIN storage_small_item_options AS item
      ON item.id = ids.item_id AND item.owner_id = parent.owner_id
    WHERE item.id IS NULL
  ) THEN
    RAISE EXCEPTION '存在引用了其他账号小项的消费记录';
  END IF;
END $$;

-- 新数据默认归当前登录账号。
ALTER TABLE customers ALTER COLUMN owner_id SET DEFAULT auth.uid();
ALTER TABLE storage_big_item_options ALTER COLUMN owner_id SET DEFAULT auth.uid();
ALTER TABLE storage_small_item_options ALTER COLUMN owner_id SET DEFAULT auth.uid();
ALTER TABLE storage_records ALTER COLUMN owner_id SET DEFAULT auth.uid();
ALTER TABLE consumption_records ALTER COLUMN owner_id SET DEFAULT auth.uid();
ALTER TABLE inventory_purchase_records ALTER COLUMN owner_id SET DEFAULT auth.uid();
ALTER TABLE inventory_consumption_records ALTER COLUMN owner_id SET DEFAULT auth.uid();
ALTER TABLE inventory_supplementary_in_records ALTER COLUMN owner_id SET DEFAULT auth.uid();

ALTER TABLE customers ALTER COLUMN owner_id SET NOT NULL;
ALTER TABLE storage_big_item_options ALTER COLUMN owner_id SET NOT NULL;
ALTER TABLE storage_small_item_options ALTER COLUMN owner_id SET NOT NULL;
ALTER TABLE storage_records ALTER COLUMN owner_id SET NOT NULL;
ALTER TABLE consumption_records ALTER COLUMN owner_id SET NOT NULL;
ALTER TABLE inventory_purchase_records ALTER COLUMN owner_id SET NOT NULL;
ALTER TABLE inventory_consumption_records ALTER COLUMN owner_id SET NOT NULL;
ALTER TABLE inventory_supplementary_in_records ALTER COLUMN owner_id SET NOT NULL;

-- 同名客户和选项可在不同账号下独立存在。
ALTER TABLE storage_records DROP CONSTRAINT IF EXISTS storage_records_customer_name_fkey;
ALTER TABLE customers DROP CONSTRAINT IF EXISTS customers_pkey;
ALTER TABLE customers ADD CONSTRAINT customers_pkey PRIMARY KEY (owner_id, name);

ALTER TABLE storage_small_item_options
  DROP CONSTRAINT IF EXISTS storage_small_item_options_name_key;
ALTER TABLE storage_small_item_options
  ADD CONSTRAINT storage_small_item_options_owner_name_key UNIQUE (owner_id, name);

ALTER TABLE storage_records
  ADD CONSTRAINT storage_records_owner_id_id_key UNIQUE (owner_id, id);
ALTER TABLE storage_small_item_options
  ADD CONSTRAINT storage_small_item_options_owner_id_id_key UNIQUE (owner_id, id);
ALTER TABLE storage_big_item_options
  ADD CONSTRAINT storage_big_item_options_owner_id_id_key UNIQUE (owner_id, id);

ALTER TABLE storage_records
  ADD CONSTRAINT storage_records_owner_customer_fkey
  FOREIGN KEY (owner_id, customer_name)
  REFERENCES customers(owner_id, name)
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE consumption_records
  DROP CONSTRAINT IF EXISTS consumption_records_storage_record_id_fkey;
ALTER TABLE consumption_records
  ADD CONSTRAINT consumption_records_owner_storage_fkey
  FOREIGN KEY (owner_id, storage_record_id)
  REFERENCES storage_records(owner_id, id)
  ON DELETE CASCADE;

ALTER TABLE consumption_records
  DROP CONSTRAINT IF EXISTS consumption_records_consumption_project_id_fkey;
ALTER TABLE consumption_records
  ADD CONSTRAINT consumption_records_owner_project_fkey
  FOREIGN KEY (owner_id, consumption_project_id)
  REFERENCES storage_small_item_options(owner_id, id)
  ON DELETE SET NULL (consumption_project_id);

ALTER TABLE storage_small_item_options
  DROP CONSTRAINT IF EXISTS storage_small_item_options_storage_big_item_id_fkey;
ALTER TABLE storage_small_item_options
  ADD CONSTRAINT storage_small_item_options_owner_big_item_fkey
  FOREIGN KEY (owner_id, storage_big_item_id)
  REFERENCES storage_big_item_options(owner_id, id)
  ON DELETE SET NULL (storage_big_item_id);

ALTER TABLE inventory_supplementary_in_records
  DROP CONSTRAINT IF EXISTS inventory_supplementary_in_records_storage_small_item_id_fkey;
ALTER TABLE inventory_supplementary_in_records
  ADD CONSTRAINT inventory_supplementary_in_owner_item_fkey
  FOREIGN KEY (owner_id, storage_small_item_id)
  REFERENCES storage_small_item_options(owner_id, id)
  ON DELETE CASCADE;

ALTER TABLE inventory_consumption_records
  DROP CONSTRAINT IF EXISTS inventory_consumption_records_storage_small_item_id_fkey;
ALTER TABLE inventory_consumption_records
  ADD CONSTRAINT inventory_consumption_owner_item_fkey
  FOREIGN KEY (owner_id, storage_small_item_id)
  REFERENCES storage_small_item_options(owner_id, id)
  ON DELETE CASCADE;

ALTER TABLE inventory_consumption_records
  DROP CONSTRAINT IF EXISTS inventory_consumption_records_source_storage_record_id_fkey;
ALTER TABLE inventory_consumption_records
  ADD CONSTRAINT inventory_consumption_owner_storage_fkey
  FOREIGN KEY (owner_id, source_storage_record_id)
  REFERENCES storage_records(owner_id, id)
  ON DELETE SET NULL (source_storage_record_id);

-- 新注册账号获得自己的默认大项，仍不会看到其他账号的选项行。
CREATE OR REPLACE FUNCTION initialize_account_big_item_options()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO storage_big_item_options (owner_id, name) VALUES
    (NEW.id, '藏红方'),
    (NEW.id, '御至宝'),
    (NEW.id, '元气植'),
    (NEW.id, '颐养年'),
    (NEW.id, '未来生物')
  ON CONFLICT (owner_id, name) DO NOTHING;
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION initialize_account_big_item_options() FROM PUBLIC;

DROP TRIGGER IF EXISTS auth_user_initialize_big_items ON auth.users;
CREATE TRIGGER auth_user_initialize_big_items
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION initialize_account_big_item_options();

-- 数组字段无法直接使用外键，使用触发器阻止跨账号小项和进货数组错位。
CREATE OR REPLACE FUNCTION validate_owned_small_item_array()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  item_id INT;
BEGIN
  IF TG_TABLE_NAME = 'inventory_purchase_records' AND
      (CARDINALITY(COALESCE(NEW.storage_small_item_ids, ARRAY[]::INT[])) = 0 OR
       CARDINALITY(COALESCE(NEW.storage_big_items, ARRAY[]::TEXT[])) <>
         CARDINALITY(COALESCE(NEW.storage_small_item_ids, ARRAY[]::INT[])) OR
       CARDINALITY(COALESCE(NEW.storage_small_item_ids, ARRAY[]::INT[])) <>
         CARDINALITY(COALESCE(NEW.quantities, ARRAY[]::INT[]))) THEN
    RAISE EXCEPTION '进货大项、小项和数量必须一一对应';
  END IF;

  FOREACH item_id IN ARRAY COALESCE(NEW.storage_small_item_ids, ARRAY[]::INT[])
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM storage_small_item_options
      WHERE id = item_id AND owner_id = NEW.owner_id
    ) THEN
      RAISE EXCEPTION '小项 % 不属于当前账号', item_id;
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION validate_owned_small_item_array() FROM PUBLIC;

DROP TRIGGER IF EXISTS storage_records_validate_owned_items ON storage_records;
CREATE TRIGGER storage_records_validate_owned_items
BEFORE INSERT OR UPDATE OF owner_id, storage_small_item_ids ON storage_records
FOR EACH ROW EXECUTE FUNCTION validate_owned_small_item_array();

DROP TRIGGER IF EXISTS inventory_purchase_validate_owned_items ON inventory_purchase_records;
CREATE TRIGGER inventory_purchase_validate_owned_items
BEFORE INSERT OR UPDATE OF owner_id, storage_big_items, storage_small_item_ids, quantities
ON inventory_purchase_records
FOR EACH ROW EXECUTE FUNCTION validate_owned_small_item_array();

CREATE OR REPLACE FUNCTION validate_owned_consumption_projects()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  item_id INT;
BEGIN
  FOREACH item_id IN ARRAY COALESCE(NEW.consumption_project_ids, ARRAY[]::INT[])
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM storage_small_item_options
      WHERE id = item_id AND owner_id = NEW.owner_id
    ) THEN
      RAISE EXCEPTION '消费小项 % 不属于当前账号', item_id;
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION validate_owned_consumption_projects() FROM PUBLIC;

DROP TRIGGER IF EXISTS consumption_records_validate_owned_projects ON consumption_records;
CREATE TRIGGER consumption_records_validate_owned_projects
BEFORE INSERT OR UPDATE OF owner_id, consumption_project_ids ON consumption_records
FOR EACH ROW EXECUTE FUNCTION validate_owned_consumption_projects();

-- 先移除业务表的全部旧策略，避免遗留宽松策略绕过隔离。
DO $$
DECLARE
  policy_row RECORD;
BEGIN
  FOR policy_row IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN (
        'customers',
        'storage_big_item_options',
        'storage_small_item_options',
        'storage_records',
        'consumption_records',
        'inventory_purchase_records',
        'inventory_consumption_records',
        'inventory_supplementary_in_records',
        'push_devices'
      )
  LOOP
    EXECUTE format(
      'DROP POLICY %I ON %I.%I',
      policy_row.policyname,
      policy_row.schemaname,
      policy_row.tablename
    );
  END LOOP;
END $$;

CREATE POLICY customers_owner_only ON customers
  FOR ALL TO authenticated USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());
CREATE POLICY storage_big_item_options_owner_only ON storage_big_item_options
  FOR ALL TO authenticated USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());
CREATE POLICY storage_small_item_options_owner_only ON storage_small_item_options
  FOR ALL TO authenticated USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());
CREATE POLICY storage_records_owner_only ON storage_records
  FOR ALL TO authenticated USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());
CREATE POLICY consumption_records_owner_only ON consumption_records
  FOR ALL TO authenticated USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());
CREATE POLICY inventory_purchase_records_owner_only ON inventory_purchase_records
  FOR ALL TO authenticated USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());
CREATE POLICY inventory_consumption_records_owner_only ON inventory_consumption_records
  FOR ALL TO authenticated USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());
CREATE POLICY inventory_supp_in_owner_only ON inventory_supplementary_in_records
  FOR ALL TO authenticated USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());
CREATE POLICY push_devices_owner_only ON push_devices
  FOR ALL TO authenticated USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

ALTER TABLE push_devices ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_customers_owner ON customers(owner_id);
CREATE INDEX IF NOT EXISTS idx_storage_records_owner_date
  ON storage_records(owner_id, storage_date DESC);
CREATE INDEX IF NOT EXISTS idx_consumption_records_owner_date
  ON consumption_records(owner_id, consumption_date DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_purchase_owner_date
  ON inventory_purchase_records(owner_id, purchase_date DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_consumption_owner_date
  ON inventory_consumption_records(owner_id, consumption_date DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_supp_in_owner_date
  ON inventory_supplementary_in_records(owner_id, supplement_date DESC);
CREATE INDEX IF NOT EXISTS idx_push_devices_owner
  ON push_devices(owner_id) WHERE is_active;

COMMIT;

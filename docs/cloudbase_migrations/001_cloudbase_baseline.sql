BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '5min';

DO $$
DECLARE
  v_existing_count integer;
BEGIN
  SELECT count(*)
  INTO v_existing_count
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_name IN (
      'customers',
      'storage_big_item_options',
      'storage_small_item_options',
      'storage_records',
      'consumption_records',
      'inventory_purchase_records',
      'inventory_supplementary_in_records',
      'inventory_consumption_records',
      'push_devices'
    );

  IF v_existing_count <> 0 THEN
    RAISE EXCEPTION
      'CloudBase 基线已停止：public 中已存在 % 张目标业务表，请先核对环境，禁止覆盖执行',
      v_existing_count;
  END IF;

  IF to_regprocedure('auth.uid()') IS NULL THEN
    RAISE EXCEPTION 'CloudBase 基线已停止：缺少 auth.uid()';
  END IF;

  IF pg_get_function_result('auth.uid()'::regprocedure) <> 'text' THEN
    RAISE EXCEPTION
      'CloudBase 基线已停止：auth.uid() 返回类型不是 text，当前为 %',
      pg_get_function_result('auth.uid()'::regprocedure);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    RAISE EXCEPTION 'CloudBase 基线已停止：缺少 authenticated 角色';
  END IF;
END $$;

CREATE SEQUENCE storage_code_seq START 1;
CREATE SEQUENCE consumption_code_seq START 1;
CREATE SEQUENCE inventory_purchase_code_seq START 1;

CREATE TABLE customers (
  owner_id text NOT NULL DEFAULT auth.uid(),
  name text NOT NULL,
  phone text,
  lunar_birthday text,
  solar_birthday date,
  zodiac text,
  age integer,
  address text,
  life_number integer,
  symptoms text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT customers_pkey PRIMARY KEY (owner_id, name)
);

CREATE TABLE storage_big_item_options (
  id serial PRIMARY KEY,
  owner_id text NOT NULL DEFAULT auth.uid(),
  name text NOT NULL,
  CONSTRAINT storage_big_item_options_owner_name_key UNIQUE (owner_id, name),
  CONSTRAINT storage_big_item_options_owner_id_id_key UNIQUE (owner_id, id)
);

CREATE TABLE storage_small_item_options (
  id serial PRIMARY KEY,
  owner_id text NOT NULL DEFAULT auth.uid(),
  name text NOT NULL,
  storage_big_item_id integer,
  CONSTRAINT storage_small_item_options_owner_name_key UNIQUE (owner_id, name),
  CONSTRAINT storage_small_item_options_owner_id_id_key UNIQUE (owner_id, id),
  CONSTRAINT storage_small_item_options_owner_big_item_fkey
    FOREIGN KEY (owner_id, storage_big_item_id)
    REFERENCES storage_big_item_options(owner_id, id)
    ON DELETE SET NULL (storage_big_item_id)
);

CREATE TABLE storage_records (
  id serial PRIMARY KEY,
  owner_id text NOT NULL DEFAULT auth.uid(),
  code text NOT NULL,
  customer_name text NOT NULL,
  storage_big_items text[] NOT NULL DEFAULT '{}'::text[],
  storage_small_item_ids integer[] NOT NULL DEFAULT '{}'::integer[],
  amount numeric(12, 2) NOT NULL DEFAULT 0,
  total_count integer NOT NULL DEFAULT 0,
  storage_date date NOT NULL DEFAULT current_date,
  remark text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT storage_records_owner_code_key UNIQUE (owner_id, code),
  CONSTRAINT storage_records_owner_id_id_key UNIQUE (owner_id, id),
  CONSTRAINT storage_records_owner_customer_fkey
    FOREIGN KEY (owner_id, customer_name)
    REFERENCES customers(owner_id, name)
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE consumption_records (
  id serial PRIMARY KEY,
  owner_id text NOT NULL DEFAULT auth.uid(),
  code text NOT NULL,
  consumption_date date NOT NULL DEFAULT current_date,
  storage_record_id integer NOT NULL,
  consumption_project_id integer,
  consumption_project_ids integer[] NOT NULL DEFAULT '{}'::integer[],
  signature_url text,
  remark text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT consumption_records_owner_code_key UNIQUE (owner_id, code),
  CONSTRAINT consumption_records_owner_storage_fkey
    FOREIGN KEY (owner_id, storage_record_id)
    REFERENCES storage_records(owner_id, id)
    ON DELETE CASCADE,
  CONSTRAINT consumption_records_owner_project_fkey
    FOREIGN KEY (owner_id, consumption_project_id)
    REFERENCES storage_small_item_options(owner_id, id)
    ON DELETE SET NULL (consumption_project_id)
);

CREATE TABLE inventory_purchase_records (
  id serial PRIMARY KEY,
  owner_id text NOT NULL DEFAULT auth.uid(),
  code text NOT NULL,
  purchase_date date NOT NULL DEFAULT current_date,
  storage_big_items text[] NOT NULL DEFAULT '{}'::text[],
  storage_small_item_ids integer[] NOT NULL DEFAULT '{}'::integer[],
  quantities integer[] NOT NULL DEFAULT '{}'::integer[],
  total_amount numeric(12, 2) NOT NULL DEFAULT 0,
  remark text,
  created_at timestamptz NOT NULL DEFAULT now(),
  occurred_at timestamptz NOT NULL,
  occurred_at_is_estimated boolean NOT NULL DEFAULT false,
  voided_at timestamptz,
  voided_by text,
  void_reason text,
  CONSTRAINT inventory_purchase_owner_code_key UNIQUE (owner_id, code),
  CONSTRAINT inventory_purchase_void_audit_complete CHECK (
    (voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL)
    OR (
      voided_at IS NOT NULL
      AND voided_by IS NOT NULL
      AND void_reason IS NOT NULL
      AND btrim(void_reason) <> ''
    )
  )
);

CREATE TABLE inventory_supplementary_in_records (
  id serial PRIMARY KEY,
  owner_id text NOT NULL DEFAULT auth.uid(),
  supplement_date date NOT NULL DEFAULT current_date,
  storage_small_item_id integer NOT NULL,
  quantity integer NOT NULL,
  remark text,
  created_at timestamptz NOT NULL DEFAULT now(),
  occurred_at timestamptz NOT NULL,
  occurred_at_is_estimated boolean NOT NULL DEFAULT false,
  voided_at timestamptz,
  voided_by text,
  void_reason text,
  CONSTRAINT inventory_supplementary_in_owner_item_fkey
    FOREIGN KEY (owner_id, storage_small_item_id)
    REFERENCES storage_small_item_options(owner_id, id)
    ON DELETE RESTRICT,
  CONSTRAINT inventory_supp_in_void_audit_complete CHECK (
    (voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL)
    OR (
      voided_at IS NOT NULL
      AND voided_by IS NOT NULL
      AND void_reason IS NOT NULL
      AND btrim(void_reason) <> ''
    )
  )
);

CREATE TABLE inventory_consumption_records (
  id serial PRIMARY KEY,
  owner_id text NOT NULL DEFAULT auth.uid(),
  consumption_date date NOT NULL DEFAULT current_date,
  storage_small_item_id integer NOT NULL,
  quantity integer NOT NULL,
  remark text,
  source_storage_record_id integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  occurred_at timestamptz NOT NULL,
  occurred_at_is_estimated boolean NOT NULL DEFAULT false,
  voided_at timestamptz,
  voided_by text,
  void_reason text,
  CONSTRAINT inventory_consumption_owner_item_fkey
    FOREIGN KEY (owner_id, storage_small_item_id)
    REFERENCES storage_small_item_options(owner_id, id)
    ON DELETE RESTRICT,
  CONSTRAINT inventory_consumption_owner_storage_fkey
    FOREIGN KEY (owner_id, source_storage_record_id)
    REFERENCES storage_records(owner_id, id)
    ON DELETE SET NULL (source_storage_record_id),
  CONSTRAINT inventory_consumption_void_audit_complete CHECK (
    (voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL)
    OR (
      voided_at IS NOT NULL
      AND voided_by IS NOT NULL
      AND void_reason IS NOT NULL
      AND btrim(void_reason) <> ''
    )
  )
);

CREATE TABLE push_devices (
  id bigserial PRIMARY KEY,
  owner_id text NOT NULL DEFAULT auth.uid(),
  device_token text NOT NULL UNIQUE,
  platform text NOT NULL DEFAULT 'android',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION generate_storage_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  next_val integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '未登录，无法生成储值编号';
  END IF;
  next_val := nextval('public.storage_code_seq');
  RETURN 'CZ' || lpad(next_val::text, 5, '0');
END;
$$;

CREATE OR REPLACE FUNCTION generate_consumption_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  next_val integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '未登录，无法生成消费编号';
  END IF;
  next_val := nextval('public.consumption_code_seq');
  RETURN 'XF' || lpad(next_val::text, 5, '0');
END;
$$;

CREATE OR REPLACE FUNCTION generate_inventory_purchase_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  next_val integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '未登录，无法生成进货编号';
  END IF;
  next_val := nextval('public.inventory_purchase_code_seq');
  RETURN 'JH' || lpad(next_val::text, 5, '0');
END;
$$;

CREATE OR REPLACE FUNCTION initialize_current_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner text := auth.uid();
BEGIN
  IF v_owner IS NULL OR btrim(v_owner) = '' THEN
    RAISE EXCEPTION '未登录，无法初始化账号';
  END IF;

  INSERT INTO storage_big_item_options (owner_id, name) VALUES
    (v_owner, '藏红方'),
    (v_owner, '御至宝'),
    (v_owner, '元气植'),
    (v_owner, '颐养年'),
    (v_owner, '未来生物')
  ON CONFLICT (owner_id, name) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION claim_push_device(
  p_device_token text,
  p_platform text DEFAULT 'android'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner text := auth.uid();
BEGIN
  IF v_owner IS NULL OR btrim(v_owner) = '' THEN
    RAISE EXCEPTION '未登录，无法绑定推送设备';
  END IF;
  IF p_device_token IS NULL OR btrim(p_device_token) = '' THEN
    RAISE EXCEPTION '设备 Token 不能为空';
  END IF;

  INSERT INTO push_devices (owner_id, device_token, platform, is_active)
  VALUES (v_owner, p_device_token, COALESCE(NULLIF(btrim(p_platform), ''), 'android'), true)
  ON CONFLICT (device_token) DO UPDATE
  SET owner_id = excluded.owner_id,
      platform = excluded.platform,
      is_active = true;
END;
$$;

CREATE OR REPLACE FUNCTION release_push_device(p_device_token text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE push_devices
  SET is_active = false
  WHERE device_token = p_device_token
    AND owner_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION validate_owned_small_item_array()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  item_id integer;
BEGIN
  IF TG_TABLE_NAME = 'inventory_purchase_records' THEN
    IF cardinality(COALESCE(NEW.storage_small_item_ids, ARRAY[]::integer[])) = 0
      OR cardinality(COALESCE(NEW.storage_big_items, ARRAY[]::text[])) <>
         cardinality(COALESCE(NEW.storage_small_item_ids, ARRAY[]::integer[]))
      OR cardinality(COALESCE(NEW.storage_small_item_ids, ARRAY[]::integer[])) <>
         cardinality(COALESCE(NEW.quantities, ARRAY[]::integer[])) THEN
      RAISE EXCEPTION '进货大项、小项和数量必须一一对应';
    END IF;

    IF TG_OP = 'UPDATE'
      AND NEW.owner_id IS NOT DISTINCT FROM OLD.owner_id
      AND NEW.storage_big_items IS NOT DISTINCT FROM OLD.storage_big_items
      AND NEW.storage_small_item_ids IS NOT DISTINCT FROM OLD.storage_small_item_ids
      AND NEW.quantities IS NOT DISTINCT FROM OLD.quantities THEN
      RETURN NEW;
    END IF;
  END IF;

  FOREACH item_id IN ARRAY COALESCE(NEW.storage_small_item_ids, ARRAY[]::integer[])
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM storage_small_item_options
      WHERE id = item_id AND owner_id = NEW.owner_id
    ) THEN
      RAISE EXCEPTION '小项 % 已删除或不属于当前账号，请重新选择当前商品', item_id;
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_owned_consumption_projects()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  item_id integer;
BEGIN
  FOREACH item_id IN ARRAY COALESCE(NEW.consumption_project_ids, ARRAY[]::integer[])
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM storage_small_item_options
      WHERE id = item_id AND owner_id = NEW.owner_id
    ) THEN
      RAISE EXCEPTION '消费小项 % 不属于当前账号', item_id;
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION prevent_referenced_small_item_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM storage_records
    WHERE owner_id = OLD.owner_id
      AND OLD.id = ANY(COALESCE(storage_small_item_ids, ARRAY[]::integer[]))
  ) OR EXISTS (
    SELECT 1 FROM consumption_records
    WHERE owner_id = OLD.owner_id
      AND (
        consumption_project_id = OLD.id
        OR OLD.id = ANY(COALESCE(consumption_project_ids, ARRAY[]::integer[]))
      )
  ) OR EXISTS (
    SELECT 1 FROM inventory_purchase_records
    WHERE owner_id = OLD.owner_id
      AND OLD.id = ANY(COALESCE(storage_small_item_ids, ARRAY[]::integer[]))
  ) OR EXISTS (
    SELECT 1 FROM inventory_supplementary_in_records
    WHERE owner_id = OLD.owner_id AND storage_small_item_id = OLD.id
  ) OR EXISTS (
    SELECT 1 FROM inventory_consumption_records
    WHERE owner_id = OLD.owner_id AND storage_small_item_id = OLD.id
  ) THEN
    RAISE EXCEPTION '小项 % 仍被历史业务记录引用，不能删除；可改名或停止继续使用', OLD.id;
  END IF;
  RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION guard_inventory_record_audit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor text;
  v_new_business_date date;
  v_old_business_date date;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION '库存记录不可直接删除，请执行撤销操作并保留痕迹';
  END IF;

  IF TG_TABLE_NAME = 'inventory_purchase_records' THEN
    v_new_business_date := (to_jsonb(NEW) ->> 'purchase_date')::date;
    IF TG_OP = 'UPDATE' THEN
      v_old_business_date := (to_jsonb(OLD) ->> 'purchase_date')::date;
    END IF;
  ELSIF TG_TABLE_NAME = 'inventory_supplementary_in_records' THEN
    v_new_business_date := (to_jsonb(NEW) ->> 'supplement_date')::date;
    IF TG_OP = 'UPDATE' THEN
      v_old_business_date := (to_jsonb(OLD) ->> 'supplement_date')::date;
    END IF;
  ELSIF TG_TABLE_NAME = 'inventory_consumption_records' THEN
    v_new_business_date := (to_jsonb(NEW) ->> 'consumption_date')::date;
    IF TG_OP = 'UPDATE' THEN
      v_old_business_date := (to_jsonb(OLD) ->> 'consumption_date')::date;
    END IF;
  ELSE
    RAISE EXCEPTION '不支持的库存审计表：%', TG_TABLE_NAME;
  END IF;

  IF v_new_business_date IS NULL THEN
    RAISE EXCEPTION '库存记录的业务日期不能为空';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.voided_at IS NOT NULL
      OR NEW.voided_by IS NOT NULL
      OR NEW.void_reason IS NOT NULL THEN
      RAISE EXCEPTION '新建库存记录时不能直接标记为已撤销';
    END IF;
    IF NEW.occurred_at IS NULL THEN
      NEW.occurred_at := (
        v_new_business_date
        + (clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::time
      ) AT TIME ZONE 'Asia/Shanghai';
    END IF;
    NEW.occurred_at_is_estimated := false;
  ELSE
    IF OLD.voided_at IS NOT NULL THEN
      IF to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD) THEN
        RAISE EXCEPTION '已撤销的库存记录不可再次修改';
      END IF;
      RETURN NEW;
    END IF;

    IF NEW.occurred_at IS NULL THEN
      RAISE EXCEPTION '库存记录的实际发生时间不能为空';
    END IF;

    IF v_new_business_date IS DISTINCT FROM v_old_business_date
      AND NEW.occurred_at IS NOT DISTINCT FROM OLD.occurred_at THEN
      NEW.occurred_at := (
        v_new_business_date
        + (OLD.occurred_at AT TIME ZONE 'Asia/Shanghai')::time
      ) AT TIME ZONE 'Asia/Shanghai';
    END IF;
  END IF;

  IF (NEW.occurred_at AT TIME ZONE 'Asia/Shanghai')::date
      IS DISTINCT FROM v_new_business_date THEN
    RAISE EXCEPTION '库存记录的业务日期必须与实际发生时间处于同一天';
  END IF;

  IF TG_OP = 'UPDATE'
    AND OLD.voided_at IS NULL
    AND NEW.voided_at IS NOT NULL THEN
    IF NEW.void_reason IS NULL OR btrim(NEW.void_reason) = '' THEN
      RAISE EXCEPTION '撤销库存记录时必须填写原因';
    END IF;

    IF (
      to_jsonb(NEW) - ARRAY['voided_at', 'voided_by', 'void_reason']
    ) IS DISTINCT FROM (
      to_jsonb(OLD) - ARRAY['voided_at', 'voided_by', 'void_reason']
    ) THEN
      RAISE EXCEPTION '撤销库存记录时不能同时修改原始业务数据';
    END IF;

    v_actor := auth.uid();
    IF v_actor IS NULL OR btrim(v_actor) = '' THEN
      RAISE EXCEPTION '未登录，无法撤销库存记录';
    END IF;

    NEW.voided_at := clock_timestamp();
    NEW.voided_by := v_actor;
    NEW.void_reason := btrim(NEW.void_reason);
  ELSIF TG_OP = 'UPDATE' AND (
    NEW.voided_at IS DISTINCT FROM OLD.voided_at
    OR NEW.voided_by IS DISTINCT FROM OLD.voided_by
    OR NEW.void_reason IS DISTINCT FROM OLD.void_reason
  ) THEN
    RAISE EXCEPTION '撤销审计字段只能通过一次有效撤销操作写入';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER storage_records_validate_owned_items
BEFORE INSERT OR UPDATE OF owner_id, storage_small_item_ids ON storage_records
FOR EACH ROW EXECUTE FUNCTION validate_owned_small_item_array();

CREATE TRIGGER inventory_purchase_validate_owned_items
BEFORE INSERT OR UPDATE OF owner_id, storage_big_items, storage_small_item_ids, quantities
ON inventory_purchase_records
FOR EACH ROW EXECUTE FUNCTION validate_owned_small_item_array();

CREATE TRIGGER consumption_records_validate_owned_projects
BEFORE INSERT OR UPDATE OF owner_id, consumption_project_ids ON consumption_records
FOR EACH ROW EXECUTE FUNCTION validate_owned_consumption_projects();

CREATE TRIGGER storage_small_item_prevent_referenced_delete
BEFORE DELETE ON storage_small_item_options
FOR EACH ROW EXECUTE FUNCTION prevent_referenced_small_item_delete();

CREATE TRIGGER inventory_purchase_audit_guard
BEFORE INSERT OR UPDATE OR DELETE ON inventory_purchase_records
FOR EACH ROW EXECUTE FUNCTION guard_inventory_record_audit();

CREATE TRIGGER inventory_supp_in_audit_guard
BEFORE INSERT OR UPDATE OR DELETE ON inventory_supplementary_in_records
FOR EACH ROW EXECUTE FUNCTION guard_inventory_record_audit();

CREATE TRIGGER inventory_consumption_audit_guard
BEFORE INSERT OR UPDATE OR DELETE ON inventory_consumption_records
FOR EACH ROW EXECUTE FUNCTION guard_inventory_record_audit();

CREATE INDEX idx_storage_small_item_big_item
  ON storage_small_item_options(owner_id, storage_big_item_id);
CREATE INDEX idx_storage_records_customer
  ON storage_records(owner_id, customer_name);
CREATE INDEX idx_storage_records_owner_date
  ON storage_records(owner_id, storage_date DESC, id DESC);
CREATE INDEX idx_consumption_records_owner_date
  ON consumption_records(owner_id, consumption_date DESC, id DESC);
CREATE INDEX idx_consumption_records_storage
  ON consumption_records(owner_id, storage_record_id);
CREATE INDEX idx_inventory_purchase_owner_timeline
  ON inventory_purchase_records(owner_id, purchase_date DESC, occurred_at DESC, id DESC);
CREATE INDEX idx_inventory_supp_in_owner_timeline
  ON inventory_supplementary_in_records(owner_id, supplement_date DESC, occurred_at DESC, id DESC);
CREATE INDEX idx_inventory_supp_in_owner_item
  ON inventory_supplementary_in_records(owner_id, storage_small_item_id);
CREATE INDEX idx_inventory_consumption_owner_timeline
  ON inventory_consumption_records(owner_id, consumption_date DESC, occurred_at DESC, id DESC);
CREATE INDEX idx_inventory_consumption_owner_item
  ON inventory_consumption_records(owner_id, storage_small_item_id);
CREATE INDEX idx_inventory_consumption_owner_storage
  ON inventory_consumption_records(owner_id, source_storage_record_id);
CREATE INDEX idx_push_devices_owner
  ON push_devices(owner_id) WHERE is_active;

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage_big_item_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage_small_item_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE consumption_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_purchase_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_supplementary_in_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_consumption_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY customers_owner_only ON customers
  FOR ALL TO authenticated
  USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
CREATE POLICY storage_big_item_options_owner_only ON storage_big_item_options
  FOR ALL TO authenticated
  USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
CREATE POLICY storage_small_item_options_owner_only ON storage_small_item_options
  FOR ALL TO authenticated
  USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
CREATE POLICY storage_records_owner_only ON storage_records
  FOR ALL TO authenticated
  USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
CREATE POLICY consumption_records_owner_only ON consumption_records
  FOR ALL TO authenticated
  USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
CREATE POLICY inventory_purchase_records_owner_only ON inventory_purchase_records
  FOR ALL TO authenticated
  USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
CREATE POLICY inventory_supp_in_owner_only ON inventory_supplementary_in_records
  FOR ALL TO authenticated
  USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
CREATE POLICY inventory_consumption_records_owner_only ON inventory_consumption_records
  FOR ALL TO authenticated
  USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
CREATE POLICY push_devices_owner_only ON push_devices
  FOR ALL TO authenticated
  USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());

REVOKE ALL ON
  customers,
  storage_big_item_options,
  storage_small_item_options,
  storage_records,
  consumption_records,
  inventory_purchase_records,
  inventory_supplementary_in_records,
  inventory_consumption_records,
  push_devices
FROM anon;
REVOKE ALL ON SEQUENCE
  storage_code_seq,
  consumption_code_seq,
  inventory_purchase_code_seq,
  storage_big_item_options_id_seq,
  storage_small_item_options_id_seq,
  storage_records_id_seq,
  consumption_records_id_seq,
  inventory_purchase_records_id_seq,
  inventory_supplementary_in_records_id_seq,
  inventory_consumption_records_id_seq,
  push_devices_id_seq
FROM anon;

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON
  customers,
  storage_big_item_options,
  storage_small_item_options,
  storage_records,
  consumption_records,
  inventory_purchase_records,
  inventory_supplementary_in_records,
  inventory_consumption_records,
  push_devices
TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

REVOKE ALL ON FUNCTION generate_storage_code() FROM PUBLIC;
REVOKE ALL ON FUNCTION generate_consumption_code() FROM PUBLIC;
REVOKE ALL ON FUNCTION generate_inventory_purchase_code() FROM PUBLIC;
REVOKE ALL ON FUNCTION initialize_current_account() FROM PUBLIC;
REVOKE ALL ON FUNCTION claim_push_device(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION release_push_device(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION validate_owned_small_item_array() FROM PUBLIC;
REVOKE ALL ON FUNCTION validate_owned_consumption_projects() FROM PUBLIC;
REVOKE ALL ON FUNCTION prevent_referenced_small_item_delete() FROM PUBLIC;
REVOKE ALL ON FUNCTION guard_inventory_record_audit() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION generate_storage_code() TO authenticated;
GRANT EXECUTE ON FUNCTION generate_consumption_code() TO authenticated;
GRANT EXECUTE ON FUNCTION generate_inventory_purchase_code() TO authenticated;
GRANT EXECUTE ON FUNCTION initialize_current_account() TO authenticated;
GRANT EXECUTE ON FUNCTION claim_push_device(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION release_push_device(text) TO authenticated;

COMMIT;

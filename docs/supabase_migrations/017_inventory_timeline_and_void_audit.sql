-- 颐养年 - 库存时间线与撤销留痕（生产加固版）
--
-- 目标：
-- 1. 不改写历史业务日期、不删除历史记录，为三类库存来源补充统一排序字段。
-- 2. 撤销动作由数据库记录真实操作人和时间，撤销后禁止再次编辑或物理删除。
-- 3. 兼容未升级客户端：未传 occurred_at 时，按业务日期和当前本地时刻生成。
--
-- 执行前必须满足：
-- 1. 已完成 Supabase 数据库级备份或 PITR；CSV 只能作为业务数据副本，不能替代完整备份。
-- 2. 已成功执行 016_account_isolation.sql，并确认三张库存表只允许账号访问自己的数据。
-- 3. 选择低峰期执行。任何前置检查或加锁失败都会报错停止，请勿跳过检查强行执行。

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '5min';

-- 017 依赖 016。这里不仅检查字段和策略名，也检查 RLS 已启用、策略条件正确，
-- 防止旧的 USING (true) 宽松策略仍然在线上生效。
DO $$
DECLARE
  v_owner_column_count INTEGER;
  v_rls_table_count INTEGER;
  v_inventory_policy_count INTEGER;
  v_owner_policy_count INTEGER;
BEGIN
  SELECT COUNT(*)
  INTO v_owner_column_count
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name IN (
      'inventory_purchase_records',
      'inventory_supplementary_in_records',
      'inventory_consumption_records'
    )
    AND column_name = 'owner_id';

  IF v_owner_column_count <> 3 THEN
    RAISE EXCEPTION '017 已停止：三张库存表尚未完整执行 016（缺少 owner_id）';
  END IF;

  SELECT COUNT(*)
  INTO v_rls_table_count
  FROM pg_class AS table_row
  JOIN pg_namespace AS schema_row
    ON schema_row.oid = table_row.relnamespace
  WHERE schema_row.nspname = 'public'
    AND table_row.relname IN (
      'inventory_purchase_records',
      'inventory_supplementary_in_records',
      'inventory_consumption_records'
    )
    AND table_row.relrowsecurity;

  IF v_rls_table_count <> 3 THEN
    RAISE EXCEPTION '017 已停止：三张库存表必须全部启用 RLS';
  END IF;

  SELECT COUNT(*)
  INTO v_inventory_policy_count
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename IN (
      'inventory_purchase_records',
      'inventory_supplementary_in_records',
      'inventory_consumption_records'
    );

  IF v_inventory_policy_count <> 3 THEN
    RAISE EXCEPTION '017 已停止：库存表存在缺失或额外的访问策略，请先重新核对 016';
  END IF;

  SELECT COUNT(*)
  INTO v_owner_policy_count
  FROM pg_policies
  WHERE schemaname = 'public'
    AND (
      (tablename = 'inventory_purchase_records'
        AND policyname = 'inventory_purchase_records_owner_only')
      OR (tablename = 'inventory_supplementary_in_records'
        AND policyname = 'inventory_supp_in_owner_only')
      OR (tablename = 'inventory_consumption_records'
        AND policyname = 'inventory_consumption_records_owner_only')
    )
    AND cmd = 'ALL'
    AND 'authenticated' = ANY (roles)
    AND regexp_replace(lower(COALESCE(qual, '')), '[[:space:]()]', '', 'g')
      = 'owner_id=auth.uid'
    AND regexp_replace(lower(COALESCE(with_check, '')), '[[:space:]()]', '', 'g')
      = 'owner_id=auth.uid';

  IF v_owner_policy_count <> 3 THEN
    RAISE EXCEPTION '017 已停止：016 的账号隔离策略缺失或条件不正确';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN (
        'inventory_purchase_records',
        'inventory_supplementary_in_records',
        'inventory_consumption_records'
      )
      AND (
        regexp_replace(lower(COALESCE(qual, '')), '[[:space:]()]', '', 'g') = 'true'
        OR regexp_replace(lower(COALESCE(with_check, '')), '[[:space:]()]', '', 'g') = 'true'
      )
  ) THEN
    RAISE EXCEPTION '017 已停止：检测到允许所有账号访问的宽松库存策略';
  END IF;

  IF EXISTS (SELECT 1 FROM inventory_purchase_records WHERE owner_id IS NULL)
    OR EXISTS (SELECT 1 FROM inventory_supplementary_in_records WHERE owner_id IS NULL)
    OR EXISTS (SELECT 1 FROM inventory_consumption_records WHERE owner_id IS NULL) THEN
    RAISE EXCEPTION '017 已停止：库存历史记录仍存在未归属账号的数据';
  END IF;
END $$;

ALTER TABLE inventory_purchase_records
  ADD COLUMN IF NOT EXISTS occurred_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS occurred_at_is_estimated BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS voided_by UUID,
  ADD COLUMN IF NOT EXISTS void_reason TEXT;

ALTER TABLE inventory_supplementary_in_records
  ADD COLUMN IF NOT EXISTS occurred_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS occurred_at_is_estimated BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS voided_by UUID,
  ADD COLUMN IF NOT EXISTS void_reason TEXT;

ALTER TABLE inventory_consumption_records
  ADD COLUMN IF NOT EXISTS occurred_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS occurred_at_is_estimated BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS voided_by UUID,
  ADD COLUMN IF NOT EXISTS void_reason TEXT;

-- 如果旧版 017 曾经部分执行，移除对 auth.users 的级联生命周期依赖。
-- voided_by 是审计快照：账号未来即使删除，也应保留当时的 UUID。
ALTER TABLE inventory_purchase_records
  DROP CONSTRAINT IF EXISTS inventory_purchase_records_voided_by_fkey,
  ALTER COLUMN occurred_at DROP DEFAULT;
ALTER TABLE inventory_supplementary_in_records
  DROP CONSTRAINT IF EXISTS inventory_supplementary_in_records_voided_by_fkey,
  ALTER COLUMN occurred_at DROP DEFAULT;
ALTER TABLE inventory_consumption_records
  DROP CONSTRAINT IF EXISTS inventory_consumption_records_voided_by_fkey,
  ALTER COLUMN occurred_at DROP DEFAULT;

-- 历史数据只有日期，没有可靠的跨表时刻。按已确认规则回填：
-- 进货入库 09:00、补充入库 12:00、出库 18:00；同账号、同类型内再按创建时间和 ID 排序。
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY owner_id, purchase_date
      ORDER BY created_at NULLS LAST, id
    ) AS row_no
  FROM inventory_purchase_records
  WHERE occurred_at IS NULL
)
UPDATE inventory_purchase_records AS target
SET
  occurred_at = (
    target.purchase_date + TIME '09:00:00' +
    (ranked.row_no - 1) * INTERVAL '1 millisecond'
  ) AT TIME ZONE 'Asia/Shanghai',
  occurred_at_is_estimated = TRUE
FROM ranked
WHERE target.id = ranked.id;

WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY owner_id, supplement_date
      ORDER BY created_at NULLS LAST, id
    ) AS row_no
  FROM inventory_supplementary_in_records
  WHERE occurred_at IS NULL
)
UPDATE inventory_supplementary_in_records AS target
SET
  occurred_at = (
    target.supplement_date + TIME '12:00:00' +
    (ranked.row_no - 1) * INTERVAL '1 millisecond'
  ) AT TIME ZONE 'Asia/Shanghai',
  occurred_at_is_estimated = TRUE
FROM ranked
WHERE target.id = ranked.id;

WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY owner_id, consumption_date
      ORDER BY created_at NULLS LAST, id
    ) AS row_no
  FROM inventory_consumption_records
  WHERE occurred_at IS NULL
)
UPDATE inventory_consumption_records AS target
SET
  occurred_at = (
    target.consumption_date + TIME '18:00:00' +
    (ranked.row_no - 1) * INTERVAL '1 millisecond'
  ) AT TIME ZONE 'Asia/Shanghai',
  occurred_at_is_estimated = TRUE
FROM ranked
WHERE target.id = ranked.id;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM inventory_purchase_records WHERE occurred_at IS NULL)
    OR EXISTS (SELECT 1 FROM inventory_supplementary_in_records WHERE occurred_at IS NULL)
    OR EXISTS (SELECT 1 FROM inventory_consumption_records WHERE occurred_at IS NULL) THEN
    RAISE EXCEPTION '017 已停止：历史时间回填不完整';
  END IF;
END $$;

ALTER TABLE inventory_purchase_records
  ALTER COLUMN occurred_at SET NOT NULL;
ALTER TABLE inventory_supplementary_in_records
  ALTER COLUMN occurred_at SET NOT NULL;
ALTER TABLE inventory_consumption_records
  ALTER COLUMN occurred_at SET NOT NULL;

-- 三个撤销字段必须同时为空或同时有效；显式检查 void_reason IS NOT NULL，
-- 避免 PostgreSQL CHECK 对 NULL 结果放行。
ALTER TABLE inventory_purchase_records
  DROP CONSTRAINT IF EXISTS inventory_purchase_void_audit_complete;
ALTER TABLE inventory_purchase_records
  ADD CONSTRAINT inventory_purchase_void_audit_complete CHECK (
    (voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL)
    OR (
      voided_at IS NOT NULL
      AND voided_by IS NOT NULL
      AND void_reason IS NOT NULL
      AND BTRIM(void_reason) <> ''
    )
  ) NOT VALID;
ALTER TABLE inventory_purchase_records
  VALIDATE CONSTRAINT inventory_purchase_void_audit_complete;

ALTER TABLE inventory_supplementary_in_records
  DROP CONSTRAINT IF EXISTS inventory_supp_in_void_audit_complete;
ALTER TABLE inventory_supplementary_in_records
  ADD CONSTRAINT inventory_supp_in_void_audit_complete CHECK (
    (voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL)
    OR (
      voided_at IS NOT NULL
      AND voided_by IS NOT NULL
      AND void_reason IS NOT NULL
      AND BTRIM(void_reason) <> ''
    )
  ) NOT VALID;
ALTER TABLE inventory_supplementary_in_records
  VALIDATE CONSTRAINT inventory_supp_in_void_audit_complete;

ALTER TABLE inventory_consumption_records
  DROP CONSTRAINT IF EXISTS inventory_consumption_void_audit_complete;
ALTER TABLE inventory_consumption_records
  ADD CONSTRAINT inventory_consumption_void_audit_complete CHECK (
    (voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL)
    OR (
      voided_at IS NOT NULL
      AND voided_by IS NOT NULL
      AND void_reason IS NOT NULL
      AND BTRIM(void_reason) <> ''
    )
  ) NOT VALID;
ALTER TABLE inventory_consumption_records
  VALIDATE CONSTRAINT inventory_consumption_void_audit_complete;

CREATE OR REPLACE FUNCTION public.guard_inventory_record_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor UUID;
  v_new_business_date DATE;
  v_old_business_date DATE;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION '库存记录不可直接删除，请执行撤销操作并保留痕迹';
  END IF;

  IF TG_TABLE_NAME = 'inventory_purchase_records' THEN
    v_new_business_date := (to_jsonb(NEW) ->> 'purchase_date')::DATE;
    IF TG_OP = 'UPDATE' THEN
      v_old_business_date := (to_jsonb(OLD) ->> 'purchase_date')::DATE;
    END IF;
  ELSIF TG_TABLE_NAME = 'inventory_supplementary_in_records' THEN
    v_new_business_date := (to_jsonb(NEW) ->> 'supplement_date')::DATE;
    IF TG_OP = 'UPDATE' THEN
      v_old_business_date := (to_jsonb(OLD) ->> 'supplement_date')::DATE;
    END IF;
  ELSIF TG_TABLE_NAME = 'inventory_consumption_records' THEN
    v_new_business_date := (to_jsonb(NEW) ->> 'consumption_date')::DATE;
    IF TG_OP = 'UPDATE' THEN
      v_old_business_date := (to_jsonb(OLD) ->> 'consumption_date')::DATE;
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

    -- 旧客户端没有 occurred_at 字段时，仍按用户填写的业务日期落库，
    -- 而不是错误地使用服务器当天日期。
    IF NEW.occurred_at IS NULL THEN
      NEW.occurred_at := (
        v_new_business_date +
        (clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::TIME
      ) AT TIME ZONE 'Asia/Shanghai';
    END IF;
    NEW.occurred_at_is_estimated := FALSE;
  ELSE
    -- 撤销完成后整条记录冻结，不能恢复、改内容或篡改审计字段。
    IF OLD.voided_at IS NOT NULL THEN
      IF to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD) THEN
        RAISE EXCEPTION '已撤销的库存记录不可再次修改';
      END IF;
      RETURN NEW;
    END IF;

    IF NEW.occurred_at IS NULL THEN
      RAISE EXCEPTION '库存记录的实际发生时间不能为空';
    END IF;

    -- 兼容旧客户端修改业务日期但没有同步 occurred_at 的情况：
    -- 保留原本的本地时刻，只把记录移动到新的业务日期。
    IF v_new_business_date IS DISTINCT FROM v_old_business_date
      AND NEW.occurred_at IS NOT DISTINCT FROM OLD.occurred_at THEN
      NEW.occurred_at := (
        v_new_business_date +
        (OLD.occurred_at AT TIME ZONE 'Asia/Shanghai')::TIME
      ) AT TIME ZONE 'Asia/Shanghai';
    END IF;
  END IF;

  IF (NEW.occurred_at AT TIME ZONE 'Asia/Shanghai')::DATE
      IS DISTINCT FROM v_new_business_date THEN
    RAISE EXCEPTION '库存记录的业务日期必须与实际发生时间处于同一天';
  END IF;

  IF TG_OP = 'UPDATE'
    AND OLD.voided_at IS NULL
    AND NEW.voided_at IS NOT NULL THEN
    IF NEW.void_reason IS NULL OR BTRIM(NEW.void_reason) = '' THEN
      RAISE EXCEPTION '撤销库存记录时必须填写原因';
    END IF;

    -- 一次请求只能执行撤销，不能同时夹带修改原始业务数据。
    IF (
      to_jsonb(NEW) - ARRAY['voided_at', 'voided_by', 'void_reason']
    ) IS DISTINCT FROM (
      to_jsonb(OLD) - ARRAY['voided_at', 'voided_by', 'void_reason']
    ) THEN
      RAISE EXCEPTION '撤销库存记录时不能同时修改原始业务数据';
    END IF;

    v_actor := auth.uid();
    IF v_actor IS NULL THEN
      RAISE EXCEPTION '未登录，无法撤销库存记录';
    END IF;

    -- 忽略客户端传入的时间和用户，统一使用数据库可信上下文。
    NEW.voided_at := clock_timestamp();
    NEW.voided_by := v_actor;
    NEW.void_reason := BTRIM(NEW.void_reason);
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

REVOKE ALL ON FUNCTION public.guard_inventory_record_audit() FROM PUBLIC;

-- 清理旧版 017 的单一删除触发器，再安装覆盖新增、编辑、撤销、删除的统一保护。
DROP TRIGGER IF EXISTS inventory_purchase_prevent_delete
  ON inventory_purchase_records;
DROP TRIGGER IF EXISTS inventory_supp_in_prevent_delete
  ON inventory_supplementary_in_records;
DROP TRIGGER IF EXISTS inventory_consumption_prevent_delete
  ON inventory_consumption_records;

DROP TRIGGER IF EXISTS inventory_purchase_audit_guard
  ON inventory_purchase_records;
CREATE TRIGGER inventory_purchase_audit_guard
BEFORE INSERT OR UPDATE OR DELETE ON inventory_purchase_records
FOR EACH ROW EXECUTE FUNCTION public.guard_inventory_record_audit();

DROP TRIGGER IF EXISTS inventory_supp_in_audit_guard
  ON inventory_supplementary_in_records;
CREATE TRIGGER inventory_supp_in_audit_guard
BEFORE INSERT OR UPDATE OR DELETE ON inventory_supplementary_in_records
FOR EACH ROW EXECUTE FUNCTION public.guard_inventory_record_audit();

DROP TRIGGER IF EXISTS inventory_consumption_audit_guard
  ON inventory_consumption_records;
CREATE TRIGGER inventory_consumption_audit_guard
BEFORE INSERT OR UPDATE OR DELETE ON inventory_consumption_records
FOR EACH ROW EXECUTE FUNCTION public.guard_inventory_record_audit();

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM inventory_purchase_records
    WHERE (occurred_at AT TIME ZONE 'Asia/Shanghai')::DATE <> purchase_date
  ) OR EXISTS (
    SELECT 1
    FROM inventory_supplementary_in_records
    WHERE (occurred_at AT TIME ZONE 'Asia/Shanghai')::DATE <> supplement_date
  ) OR EXISTS (
    SELECT 1
    FROM inventory_consumption_records
    WHERE (occurred_at AT TIME ZONE 'Asia/Shanghai')::DATE <> consumption_date
  ) THEN
    RAISE EXCEPTION '017 已停止：存在业务日期与实际发生日期不一致的库存记录';
  END IF;
END $$;

COMMIT;

-- 索引分别放在短事务中，减少一次锁等待影响全部索引。
-- 如果此处任一索引因繁忙而失败，主迁移数据已安全提交；低峰期重新运行本文件即可补齐。
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '5min';
CREATE INDEX IF NOT EXISTS idx_inventory_purchase_owner_timeline
  ON inventory_purchase_records(owner_id, purchase_date DESC, occurred_at DESC, id DESC);
COMMIT;

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '5min';
CREATE INDEX IF NOT EXISTS idx_inventory_supp_in_owner_timeline
  ON inventory_supplementary_in_records(owner_id, supplement_date DESC, occurred_at DESC, id DESC);
COMMIT;

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '5min';
CREATE INDEX IF NOT EXISTS idx_inventory_consumption_owner_timeline
  ON inventory_consumption_records(owner_id, consumption_date DESC, occurred_at DESC, id DESC);
COMMIT;

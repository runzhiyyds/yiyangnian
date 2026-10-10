-- 颐养年 - 库存时间线与撤销留痕
-- 目标：不改写历史业务日期、不删除历史记录，为三类库存来源补充统一排序与撤销审计字段。

BEGIN;

ALTER TABLE inventory_purchase_records
  ADD COLUMN IF NOT EXISTS occurred_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS occurred_at_is_estimated BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS voided_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS void_reason TEXT;

ALTER TABLE inventory_supplementary_in_records
  ADD COLUMN IF NOT EXISTS occurred_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS occurred_at_is_estimated BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS voided_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS void_reason TEXT;

ALTER TABLE inventory_consumption_records
  ADD COLUMN IF NOT EXISTS occurred_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS occurred_at_is_estimated BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS voided_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS void_reason TEXT;

-- 历史数据只有日期，没有可靠的跨表时刻。按已确认规则回填：
-- 进货入库 09:00、补充入库 12:00、出库 18:00；同类型再按创建时间和 ID 排序。
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY purchase_date
      ORDER BY created_at NULLS LAST, id
    ) AS row_no
  FROM inventory_purchase_records
  WHERE occurred_at IS NULL
)
UPDATE inventory_purchase_records AS target
SET
  occurred_at = (
    target.purchase_date + TIME '09:00:00' +
    (ranked.row_no - 1) * INTERVAL '1 second'
  ) AT TIME ZONE 'Asia/Shanghai',
  occurred_at_is_estimated = TRUE
FROM ranked
WHERE target.id = ranked.id;

WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY supplement_date
      ORDER BY created_at NULLS LAST, id
    ) AS row_no
  FROM inventory_supplementary_in_records
  WHERE occurred_at IS NULL
)
UPDATE inventory_supplementary_in_records AS target
SET
  occurred_at = (
    target.supplement_date + TIME '12:00:00' +
    (ranked.row_no - 1) * INTERVAL '1 second'
  ) AT TIME ZONE 'Asia/Shanghai',
  occurred_at_is_estimated = TRUE
FROM ranked
WHERE target.id = ranked.id;

WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY consumption_date
      ORDER BY created_at NULLS LAST, id
    ) AS row_no
  FROM inventory_consumption_records
  WHERE occurred_at IS NULL
)
UPDATE inventory_consumption_records AS target
SET
  occurred_at = (
    target.consumption_date + TIME '18:00:00' +
    (ranked.row_no - 1) * INTERVAL '1 second'
  ) AT TIME ZONE 'Asia/Shanghai',
  occurred_at_is_estimated = TRUE
FROM ranked
WHERE target.id = ranked.id;

ALTER TABLE inventory_purchase_records
  ALTER COLUMN occurred_at SET DEFAULT NOW(),
  ALTER COLUMN occurred_at SET NOT NULL;
ALTER TABLE inventory_supplementary_in_records
  ALTER COLUMN occurred_at SET DEFAULT NOW(),
  ALTER COLUMN occurred_at SET NOT NULL;
ALTER TABLE inventory_consumption_records
  ALTER COLUMN occurred_at SET DEFAULT NOW(),
  ALTER COLUMN occurred_at SET NOT NULL;

ALTER TABLE inventory_purchase_records
  DROP CONSTRAINT IF EXISTS inventory_purchase_void_audit_complete;
ALTER TABLE inventory_purchase_records
  ADD CONSTRAINT inventory_purchase_void_audit_complete CHECK (
    (voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL) OR
    (voided_at IS NOT NULL AND voided_by IS NOT NULL AND LENGTH(TRIM(void_reason)) > 0)
  );

ALTER TABLE inventory_supplementary_in_records
  DROP CONSTRAINT IF EXISTS inventory_supp_in_void_audit_complete;
ALTER TABLE inventory_supplementary_in_records
  ADD CONSTRAINT inventory_supp_in_void_audit_complete CHECK (
    (voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL) OR
    (voided_at IS NOT NULL AND voided_by IS NOT NULL AND LENGTH(TRIM(void_reason)) > 0)
  );

ALTER TABLE inventory_consumption_records
  DROP CONSTRAINT IF EXISTS inventory_consumption_void_audit_complete;
ALTER TABLE inventory_consumption_records
  ADD CONSTRAINT inventory_consumption_void_audit_complete CHECK (
    (voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL) OR
    (voided_at IS NOT NULL AND voided_by IS NOT NULL AND LENGTH(TRIM(void_reason)) > 0)
  );

CREATE INDEX IF NOT EXISTS idx_inventory_purchase_occurred_at
  ON inventory_purchase_records(occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_supp_in_occurred_at
  ON inventory_supplementary_in_records(occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_consumption_occurred_at
  ON inventory_consumption_records(occurred_at DESC);

-- 审计记录只能撤销，禁止物理删除。数据库层拦截可避免旧客户端或误操作绕过 UI。
CREATE OR REPLACE FUNCTION prevent_inventory_record_delete()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION '库存记录不可直接删除，请执行撤销操作并保留痕迹';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS inventory_purchase_prevent_delete
  ON inventory_purchase_records;
CREATE TRIGGER inventory_purchase_prevent_delete
BEFORE DELETE ON inventory_purchase_records
FOR EACH ROW EXECUTE FUNCTION prevent_inventory_record_delete();

DROP TRIGGER IF EXISTS inventory_supp_in_prevent_delete
  ON inventory_supplementary_in_records;
CREATE TRIGGER inventory_supp_in_prevent_delete
BEFORE DELETE ON inventory_supplementary_in_records
FOR EACH ROW EXECUTE FUNCTION prevent_inventory_record_delete();

DROP TRIGGER IF EXISTS inventory_consumption_prevent_delete
  ON inventory_consumption_records;
CREATE TRIGGER inventory_consumption_prevent_delete
BEFORE DELETE ON inventory_consumption_records
FOR EACH ROW EXECUTE FUNCTION prevent_inventory_record_delete();

COMMIT;

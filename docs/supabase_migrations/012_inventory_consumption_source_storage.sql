-- 库存出库记录关联来源储值（新建储值自动出库时写入）
ALTER TABLE inventory_consumption_records
  ADD COLUMN IF NOT EXISTS source_storage_record_id INT REFERENCES storage_records(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_inv_consumption_source_storage
  ON inventory_consumption_records(source_storage_record_id);

COMMENT ON COLUMN inventory_consumption_records.source_storage_record_id IS '由哪条储值记录触发的自动出库，手工出库为 NULL';

-- 颐养年 - 库存补充入库表（基于 008 扩展）
CREATE TABLE IF NOT EXISTS inventory_supplementary_in_records (
  id SERIAL PRIMARY KEY,
  supplement_date DATE NOT NULL DEFAULT CURRENT_DATE,
  storage_small_item_id INT NOT NULL REFERENCES storage_small_item_options(id) ON DELETE CASCADE,
  quantity INT NOT NULL,
  remark TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_supp_in_date ON inventory_supplementary_in_records(supplement_date);
CREATE INDEX IF NOT EXISTS idx_inventory_supp_in_item ON inventory_supplementary_in_records(storage_small_item_id);

ALTER TABLE inventory_supplementary_in_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inventory_supp_in_all" ON inventory_supplementary_in_records
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

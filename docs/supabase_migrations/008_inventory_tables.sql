-- 颐养年 - 库存管理表（与客户储值数据隔离）
-- 进货记录
CREATE TABLE IF NOT EXISTS inventory_purchase_records (
  id SERIAL PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  purchase_date DATE NOT NULL DEFAULT CURRENT_DATE,
  storage_big_items TEXT[] DEFAULT '{}',
  storage_small_item_ids INT[] DEFAULT '{}',
  quantities INT[] DEFAULT '{}',
  total_amount DECIMAL(12,2) DEFAULT 0,
  remark TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_purchase_date ON inventory_purchase_records(purchase_date);

-- 库存消耗记录（出库/报损等）
CREATE TABLE IF NOT EXISTS inventory_consumption_records (
  id SERIAL PRIMARY KEY,
  consumption_date DATE NOT NULL DEFAULT CURRENT_DATE,
  storage_small_item_id INT NOT NULL REFERENCES storage_small_item_options(id) ON DELETE CASCADE,
  quantity INT NOT NULL,
  remark TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_consumption_date ON inventory_consumption_records(consumption_date);
CREATE INDEX IF NOT EXISTS idx_inventory_consumption_item ON inventory_consumption_records(storage_small_item_id);

-- 进货编号序列
CREATE SEQUENCE IF NOT EXISTS inventory_purchase_code_seq START 1;

-- 进货编号生成：JH00001
CREATE OR REPLACE FUNCTION generate_inventory_purchase_code()
RETURNS TEXT AS $$
DECLARE
  next_val INT;
  code TEXT;
BEGIN
  next_val := nextval('inventory_purchase_code_seq');
  code := 'JH' || LPAD(next_val::TEXT, 5, '0');
  RETURN code;
END;
$$ LANGUAGE plpgsql;

-- 行级安全
ALTER TABLE inventory_purchase_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_consumption_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inventory_purchase_records_all" ON inventory_purchase_records
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "inventory_consumption_records_all" ON inventory_consumption_records
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

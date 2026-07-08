-- 颐养年 - 新建 Supabase 项目后，在 SQL Editor 中一次性执行本文件
-- 区域请选 Singapore (ap-southeast-1)，与高佳欣一致

-- ========== 1. 建表 ==========
CREATE TABLE IF NOT EXISTS customers (
  name TEXT PRIMARY KEY,
  phone TEXT,
  lunar_birthday TEXT,
  solar_birthday DATE,
  zodiac TEXT,
  age INT,
  address TEXT,
  life_number INT,
  symptoms TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS storage_small_item_options (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS storage_code_seq START 1;

CREATE TABLE IF NOT EXISTS storage_records (
  id SERIAL PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  customer_name TEXT NOT NULL REFERENCES customers(name) ON DELETE CASCADE,
  storage_big_items TEXT[] DEFAULT '{}',
  storage_small_item_ids INT[] DEFAULT '{}',
  amount DECIMAL(12, 2) NOT NULL DEFAULT 0,
  total_count INT NOT NULL DEFAULT 0,
  storage_date DATE NOT NULL DEFAULT CURRENT_DATE,
  remark TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_storage_records_customer ON storage_records(customer_name);
CREATE INDEX IF NOT EXISTS idx_storage_records_date ON storage_records(storage_date);

CREATE SEQUENCE IF NOT EXISTS consumption_code_seq START 1;

CREATE TABLE IF NOT EXISTS consumption_records (
  id SERIAL PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  consumption_date DATE NOT NULL DEFAULT CURRENT_DATE,
  storage_record_id INT NOT NULL REFERENCES storage_records(id) ON DELETE CASCADE,
  consumption_project_id INT REFERENCES storage_small_item_options(id) ON DELETE SET NULL,
  signature_url TEXT,
  remark TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_consumption_storage ON consumption_records(storage_record_id);

-- ========== 2. 编号生成函数 ==========
CREATE OR REPLACE FUNCTION generate_storage_code()
RETURNS TEXT AS $$
DECLARE next_val INT; code TEXT;
BEGIN
  next_val := nextval('storage_code_seq');
  code := 'CZ' || LPAD(next_val::TEXT, 5, '0');
  RETURN code;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION generate_consumption_code()
RETURNS TEXT AS $$
DECLARE next_val INT; code TEXT;
BEGIN
  next_val := nextval('consumption_code_seq');
  code := 'XF' || LPAD(next_val::TEXT, 5, '0');
  RETURN code;
END;
$$ LANGUAGE plpgsql;

-- ========== 3. RLS 策略 ==========
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage_small_item_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE consumption_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "customers_all" ON customers FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "storage_small_item_options_all" ON storage_small_item_options FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "storage_records_all" ON storage_records FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "consumption_records_all" ON consumption_records FOR ALL TO authenticated USING (true) WITH CHECK (true);

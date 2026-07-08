-- 颐养年客户管理系统 - 建表
-- 在 Supabase SQL Editor 中执行

-- 1. 客户表（客户姓名为主键）
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

-- 2. 储值小项选项表（动态选项）
CREATE TABLE IF NOT EXISTS storage_small_item_options (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL
);

-- 3. 储值编号序列
CREATE SEQUENCE IF NOT EXISTS storage_code_seq START 1;

-- 4. 储值记录表
CREATE TABLE IF NOT EXISTS storage_records (
  id SERIAL PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  customer_name TEXT NOT NULL REFERENCES customers(name) ON DELETE CASCADE,
  storage_big_items TEXT[] DEFAULT '{}',
  storage_small_item_ids INT[] DEFAULT '{}',
  amount DECIMAL(12, 2) NOT NULL DEFAULT 0,
  total_count INT NOT NULL DEFAULT 0,
  storage_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_storage_records_customer ON storage_records(customer_name);
CREATE INDEX IF NOT EXISTS idx_storage_records_date ON storage_records(storage_date);

-- 5. 消费编号序列
CREATE SEQUENCE IF NOT EXISTS consumption_code_seq START 1;

-- 6. 消费记录表
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

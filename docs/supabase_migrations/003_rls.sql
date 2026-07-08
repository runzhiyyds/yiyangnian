-- 颐养年 - 行级安全策略
-- 仅允许已认证用户读写（单账号共享）

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage_small_item_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE consumption_records ENABLE ROW LEVEL SECURITY;

-- 已登录用户可读写所有数据
CREATE POLICY "customers_all" ON customers
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "storage_small_item_options_all" ON storage_small_item_options
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "storage_records_all" ON storage_records
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "consumption_records_all" ON consumption_records
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

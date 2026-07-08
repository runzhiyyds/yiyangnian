-- 储值大项选项表（与储值小项能力对齐，支持用户自定义大项）
-- 储值记录表 storage_records 的 storage_big_items 仍为 TEXT[]，存大项名称
CREATE TABLE IF NOT EXISTS storage_big_item_options (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL
);

-- 插入默认大项（与原有 LunarHelper.storageBigItems 一致）
INSERT INTO storage_big_item_options (name) VALUES
  ('藏红方'),
  ('御至宝'),
  ('元气植'),
  ('颐养年'),
  ('未来生物')
ON CONFLICT (name) DO NOTHING;

-- 行级安全：已认证用户可读写
ALTER TABLE storage_big_item_options ENABLE ROW LEVEL SECURITY;

CREATE POLICY "storage_big_item_options_all" ON storage_big_item_options
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

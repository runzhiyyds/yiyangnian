-- 小项归属大项：建立大项-小项层级关系
-- 小项可选归属某个大项，便于筛选与归类管理
-- 执行顺序：先执行本文件(010)，再执行 011_backfill_small_item_big_item.sql 从历史记录继承归属
ALTER TABLE storage_small_item_options
  ADD COLUMN IF NOT EXISTS storage_big_item_id INT REFERENCES storage_big_item_options(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_small_item_big_item ON storage_small_item_options(storage_big_item_id);

COMMENT ON COLUMN storage_small_item_options.storage_big_item_id IS '归属的大项 ID，NULL 表示未归类';

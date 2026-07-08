-- 数据继承：从历史储值/进货记录中推导小项归属大项，回填 storage_big_item_id
-- 安全策略：只更新、不删除；仅回填有历史配对的；大项名不存在于选项表时跳过
-- 执行前建议：在 Supabase SQL Editor 中先执行 010，再执行本文件

BEGIN;

-- 1. 可选：备份小项表（便于回滚，生产环境建议执行）
CREATE TABLE IF NOT EXISTS storage_small_item_options_backup_20250225 AS
SELECT id, name, storage_big_item_id FROM storage_small_item_options;

-- 2. 从 storage_records 提取 (大项名, 小项ID) 配对
--    规则：大项/小项数组按索引配对；若长度不同则用第一个大项匹配所有小项
WITH sr_pairs AS (
  SELECT
    COALESCE(
      r.storage_big_items[least(gs.ord, COALESCE(array_length(r.storage_big_items, 1), 1))],
      r.storage_big_items[1]
    ) AS big_name,
    r.storage_small_item_ids[gs.ord]::int AS small_id
  FROM storage_records r
  CROSS JOIN generate_series(1, COALESCE(array_length(r.storage_small_item_ids, 1), 0)) AS gs(ord)
  WHERE COALESCE(array_length(r.storage_small_item_ids, 1), 0) > 0
    AND COALESCE(array_length(r.storage_big_items, 1), 0) > 0
    AND r.storage_small_item_ids[gs.ord] IS NOT NULL
    AND r.storage_small_item_ids[gs.ord]::int > 0
),

-- 3. 从 inventory_purchase_records 提取配对（逻辑同上）
inv_pairs AS (
  SELECT
    COALESCE(
      p.storage_big_items[least(gs.ord, COALESCE(array_length(p.storage_big_items, 1), 1))],
      p.storage_big_items[1]
    ) AS big_name,
    p.storage_small_item_ids[gs.ord]::int AS small_id
  FROM inventory_purchase_records p
  CROSS JOIN generate_series(1, COALESCE(array_length(p.storage_small_item_ids, 1), 0)) AS gs(ord)
  WHERE COALESCE(array_length(p.storage_small_item_ids, 1), 0) > 0
    AND COALESCE(array_length(p.storage_big_items, 1), 0) > 0
    AND p.storage_small_item_ids[gs.ord] IS NOT NULL
    AND p.storage_small_item_ids[gs.ord]::int > 0
),

-- 4. 合并并统计：每个 (小项ID, 大项名) 出现次数
all_pairs AS (
  SELECT big_name, small_id, count(*) AS cnt
  FROM (
    SELECT big_name, small_id FROM sr_pairs
    UNION ALL
    SELECT big_name, small_id FROM inv_pairs
  ) t
  WHERE trim(big_name) <> ''
  GROUP BY big_name, small_id
),

-- 5. 每个小项取出现次数最多的大项
best AS (
  SELECT DISTINCT ON (small_id) small_id, big_name
  FROM all_pairs
  ORDER BY small_id, cnt DESC
),

-- 6. 映射大项名 -> 大项ID（仅限 storage_big_item_options 中存在的）
mapped AS (
  SELECT b.small_id, big.id AS big_item_id
  FROM best b
  JOIN storage_big_item_options big ON big.name = trim(b.big_name)
)
UPDATE storage_small_item_options so
SET storage_big_item_id = m.big_item_id
FROM mapped m
WHERE so.id = m.small_id;

-- 7. 验证：输出回填统计（可选，执行后查看 Messages）
DO $$
DECLARE
  updated_count int;
  total_count int;
BEGIN
  SELECT count(*) INTO updated_count FROM storage_small_item_options WHERE storage_big_item_id IS NOT NULL;
  SELECT count(*) INTO total_count FROM storage_small_item_options;
  RAISE NOTICE '回填完成：已归类 % / % 个小项', updated_count, total_count;
END $$;

COMMIT;

-- 若需回滚，可执行：
-- BEGIN;
-- UPDATE storage_small_item_options so SET storage_big_item_id = b.storage_big_item_id
-- FROM storage_small_item_options_backup_20250225 b WHERE so.id = b.id;
-- COMMIT;

-- 支持单条消费记录关联多个消费项目
-- 1. 新增 consumption_project_ids 数组字段
-- 2. 用既有 consumption_project_id 初始化数组字段，兼容老数据

ALTER TABLE consumption_records
ADD COLUMN IF NOT EXISTS consumption_project_ids integer[] DEFAULT '{}'::integer[] NOT NULL;

UPDATE consumption_records
SET consumption_project_ids = ARRAY[consumption_project_id]
WHERE consumption_project_id IS NOT NULL
  AND (consumption_project_ids IS NULL OR array_length(consumption_project_ids, 1) IS NULL);


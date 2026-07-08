-- 储值记录表新增备注字段
-- 执行此迁移后，APP 才能正常保存带备注的储值记录。
-- 若未执行迁移就使用备注功能，可能触发 500 错误。
ALTER TABLE storage_records ADD COLUMN IF NOT EXISTS remark TEXT;

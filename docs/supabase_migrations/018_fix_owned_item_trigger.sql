-- 016 已执行项目的定点修复；不重跑 016、不修改业务行、RLS 或外键。
-- 执行前：保留可恢复数据库备份，并导出当前函数定义供回退。
-- SELECT pg_get_functiondef('public.validate_owned_small_item_array()'::regprocedure);
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $$
BEGIN
  IF to_regprocedure('public.validate_owned_small_item_array()') IS NULL THEN
    RAISE EXCEPTION '018 已停止：共享校验函数不存在，请先核验线上定义';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.storage_records'::regclass
      AND tgfoid = 'public.validate_owned_small_item_array()'::regprocedure
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION '018 已停止：储值表未绑定该校验函数';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.validate_owned_small_item_array()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  item_id INT;
BEGIN
  -- NEW 是动态 record；必须先分支，再访问只有进货表拥有的 quantities。
  -- AND 不保证避开 PL/pgSQL 对不存在字段的表达式准备。
  IF TG_TABLE_NAME = 'inventory_purchase_records' THEN
    IF CARDINALITY(COALESCE(NEW.storage_small_item_ids, ARRAY[]::INT[])) = 0 OR
       CARDINALITY(COALESCE(NEW.storage_big_items, ARRAY[]::TEXT[])) <>
         CARDINALITY(COALESCE(NEW.storage_small_item_ids, ARRAY[]::INT[])) OR
       CARDINALITY(COALESCE(NEW.storage_small_item_ids, ARRAY[]::INT[])) <>
         CARDINALITY(COALESCE(NEW.quantities, ARRAY[]::INT[])) THEN
      RAISE EXCEPTION '进货大项、小项和数量必须一一对应';
    END IF;

    -- 保留历史进货单只改日期、金额、备注和撤销的兼容口径。
    IF TG_OP = 'UPDATE' THEN
      IF NEW.owner_id IS NOT DISTINCT FROM OLD.owner_id
        AND NEW.storage_big_items IS NOT DISTINCT FROM OLD.storage_big_items
        AND NEW.storage_small_item_ids IS NOT DISTINCT FROM OLD.storage_small_item_ids
        AND NEW.quantities IS NOT DISTINCT FROM OLD.quantities THEN
        RETURN NEW;
      END IF;
    END IF;
  END IF;

  FOREACH item_id IN ARRAY COALESCE(NEW.storage_small_item_ids, ARRAY[]::INT[])
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM storage_small_item_options
      WHERE id = item_id AND owner_id = NEW.owner_id
    ) THEN
      RAISE EXCEPTION '小项 % 已删除或不属于当前账号，请重新选择当前商品', item_id;
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

COMMIT;

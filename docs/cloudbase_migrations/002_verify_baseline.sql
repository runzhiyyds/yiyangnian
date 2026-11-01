SELECT '业务表数量' AS 检查项, count(*)::text AS 检查结果
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'customers',
    'storage_big_item_options',
    'storage_small_item_options',
    'storage_records',
    'consumption_records',
    'inventory_purchase_records',
    'inventory_supplementary_in_records',
    'inventory_consumption_records',
    'push_devices'
  )

UNION ALL

SELECT '启用RLS的业务表数量', count(*)::text
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
    'customers',
    'storage_big_item_options',
    'storage_small_item_options',
    'storage_records',
    'consumption_records',
    'inventory_purchase_records',
    'inventory_supplementary_in_records',
    'inventory_consumption_records',
    'push_devices'
  )
  AND c.relrowsecurity

UNION ALL

SELECT 'owner_id为text的业务表数量', count(*)::text
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name = 'owner_id'
  AND data_type = 'text'
  AND table_name IN (
    'customers',
    'storage_big_item_options',
    'storage_small_item_options',
    'storage_records',
    'consumption_records',
    'inventory_purchase_records',
    'inventory_supplementary_in_records',
    'inventory_consumption_records',
    'push_devices'
  )

UNION ALL

SELECT '账号隔离策略数量', count(*)::text
FROM pg_policies
WHERE schemaname = 'public'
  AND policyname LIKE '%owner_only'

UNION ALL

SELECT '库存审计触发器数量', count(*)::text
FROM pg_trigger
WHERE tgname IN (
  'inventory_purchase_audit_guard',
  'inventory_supp_in_audit_guard',
  'inventory_consumption_audit_guard'
)
  AND NOT tgisinternal

ORDER BY 1;

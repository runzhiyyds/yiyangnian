-- 演示业务数据（客户 / 储值 / 消费 / 进货 / 库存出库 等）
-- 前置：001–012 迁移已执行；建议先执行 013_demo_auth_user.sql
-- 可重复执行：会先清除「演示-」前缀相关数据再写入

BEGIN;

-- ========== 清除旧演示数据（按依赖顺序） ==========
DELETE FROM inventory_consumption_records WHERE remark LIKE '演示%' OR remark LIKE '自动出库 · 演示-%';
DELETE FROM inventory_supplementary_in_records WHERE remark LIKE '演示%';
DELETE FROM inventory_purchase_records WHERE code LIKE 'JH90%';
DELETE FROM consumption_records WHERE code LIKE 'XF90%';
DELETE FROM storage_records WHERE code LIKE 'CZ90%' OR customer_name LIKE '演示-%';
DELETE FROM customers WHERE name LIKE '演示-%';
DELETE FROM storage_small_item_options WHERE name LIKE '演示-%';

-- ========== 写入演示数据 ==========
DO $$
DECLARE
  bid_canghong INT;
  bid_yuzhibao INT;
  bid_yiyang INT;
  sid_face INT;
  sid_shoulder INT;
  sid_qi INT;
  sid_aijiu INT;
  sid_tea INT;
  stor_zhang INT;
  stor_li INT;
  stor_wang INT;
BEGIN
  SELECT id INTO bid_canghong FROM storage_big_item_options WHERE name = '藏红方';
  SELECT id INTO bid_yuzhibao FROM storage_big_item_options WHERE name = '御至宝';
  SELECT id INTO bid_yiyang FROM storage_big_item_options WHERE name = '颐养年';

  IF bid_canghong IS NULL OR bid_yuzhibao IS NULL THEN
    RAISE EXCEPTION '请先执行 005_storage_big_item_options.sql 初始化大项';
  END IF;

  INSERT INTO storage_small_item_options (name, storage_big_item_id) VALUES
    ('演示-面部护理', bid_canghong),
    ('演示-肩颈调理', bid_canghong),
    ('演示-元气调理', bid_yuzhibao),
    ('演示-艾灸体验', bid_yuzhibao),
    ('演示-养生茶', COALESCE(bid_yiyang, bid_yuzhibao))
  ON CONFLICT (name) DO UPDATE
    SET storage_big_item_id = EXCLUDED.storage_big_item_id;

  SELECT id INTO sid_face FROM storage_small_item_options WHERE name = '演示-面部护理';
  SELECT id INTO sid_shoulder FROM storage_small_item_options WHERE name = '演示-肩颈调理';
  SELECT id INTO sid_qi FROM storage_small_item_options WHERE name = '演示-元气调理';
  SELECT id INTO sid_aijiu FROM storage_small_item_options WHERE name = '演示-艾灸体验';
  SELECT id INTO sid_tea FROM storage_small_item_options WHERE name = '演示-养生茶';

  INSERT INTO customers (name, phone, lunar_birthday, solar_birthday, zodiac, age, address, life_number, symptoms) VALUES
    ('演示-张阿姨', '13800001111', '农历正月初五', '1958-02-22', '狗', 66, '杭州市西湖区文三路', 3, '肩颈酸痛、睡眠不佳'),
    ('演示-李叔叔', '13900002222', '农历七月十八', '1965-08-15', '蛇', 59, '杭州市滨江区', 5, '腰腿不适'),
    ('演示-王姐', '13700003333', NULL, '1972-03-20', '鼠', 52, '杭州市余杭区', 8, '定期保养'),
    ('演示-陈奶奶', '13600004444', '农历冬月初八', '1950-11-08', '虎', 74, '杭州市拱墅区', 2, '需长期调理');

  -- 进货（TAB3 库存管理）
  INSERT INTO inventory_purchase_records (
    code, purchase_date, storage_big_items, storage_small_item_ids, quantities, total_amount, remark
  ) VALUES (
    'JH90001',
    (CURRENT_DATE - INTERVAL '45 days')::date,
    ARRAY['藏红方', '藏红方', '御至宝', '御至宝', '颐养年'],
    ARRAY[sid_face, sid_shoulder, sid_qi, sid_aijiu, sid_tea],
    ARRAY[30, 20, 15, 15, 25],
    18600,
    '演示进货单-首批入库'
  );

  INSERT INTO inventory_supplementary_in_records (supplement_date, storage_small_item_id, quantity, remark) VALUES
    ((CURRENT_DATE - INTERVAL '12 days')::date, sid_face, 5, '演示补充入库-面部护理'),
    ((CURRENT_DATE - INTERVAL '8 days')::date, sid_tea, 10, '演示补充入库-养生茶');

  -- 储值（TAB1 客户信息一览 / 新增储值链路）
  INSERT INTO storage_records (
    code, customer_name, storage_big_items, storage_small_item_ids,
    amount, total_count, storage_date, remark
  ) VALUES (
    'CZ90001',
    '演示-张阿姨',
    ARRAY['藏红方'],
    ARRAY[sid_face, sid_shoulder],
    8800, 20,
    (CURRENT_DATE - INTERVAL '60 days')::date,
    '演示储值-藏红方套餐'
  ) RETURNING id INTO stor_zhang;

  INSERT INTO storage_records (
    code, customer_name, storage_big_items, storage_small_item_ids,
    amount, total_count, storage_date, remark
  ) VALUES (
    'CZ90002',
    '演示-李叔叔',
    ARRAY['御至宝'],
    ARRAY[sid_qi, sid_aijiu],
    6600, 15,
    (CURRENT_DATE - INTERVAL '35 days')::date,
    '演示储值-御至宝体验'
  ) RETURNING id INTO stor_li;

  INSERT INTO storage_records (
    code, customer_name, storage_big_items, storage_small_item_ids,
    amount, total_count, storage_date, remark
  ) VALUES (
    'CZ90003',
    '演示-王姐',
    ARRAY['藏红方'],
    ARRAY[sid_face],
    3200, 8,
    (CURRENT_DATE - INTERVAL '14 days')::date,
    '演示储值-单次面部'
  ) RETURNING id INTO stor_wang;

  -- 客户消费记录（储值下消费 / 分析看板）
  INSERT INTO consumption_records (
    code, consumption_date, storage_record_id,
    consumption_project_id, consumption_project_ids, remark
  ) VALUES
    ('XF90001', (CURRENT_DATE - INTERVAL '50 days')::date, stor_zhang, sid_face, ARRAY[sid_face], '演示消费-面部护理'),
    ('XF90002', (CURRENT_DATE - INTERVAL '40 days')::date, stor_zhang, sid_shoulder, ARRAY[sid_shoulder], '演示消费-肩颈调理'),
    ('XF90003', (CURRENT_DATE - INTERVAL '28 days')::date, stor_zhang, sid_face, ARRAY[sid_face, sid_shoulder], '演示消费-组合项目'),
    ('XF90004', (CURRENT_DATE - INTERVAL '20 days')::date, stor_li, sid_qi, ARRAY[sid_qi], '演示消费-元气调理'),
    ('XF90005', (CURRENT_DATE - INTERVAL '7 days')::date, stor_wang, sid_face, ARRAY[sid_face], '演示消费-近期');

  -- 库存出库：手工 + 新建储值自动出库（TAB3 出库记录）
  INSERT INTO inventory_consumption_records (
    consumption_date, storage_small_item_id, quantity, remark, source_storage_record_id
  ) VALUES
    ((CURRENT_DATE - INTERVAL '10 days')::date, sid_face, 2, '演示手工出库-活动消耗', NULL),
    ((CURRENT_DATE - INTERVAL '60 days')::date, sid_face, 1, '自动出库 · 演示-张阿姨', stor_zhang),
    ((CURRENT_DATE - INTERVAL '60 days')::date, sid_shoulder, 1, '自动出库 · 演示-张阿姨', stor_zhang),
    ((CURRENT_DATE - INTERVAL '35 days')::date, sid_qi, 1, '自动出库 · 演示-李叔叔', stor_li),
    ((CURRENT_DATE - INTERVAL '35 days')::date, sid_aijiu, 1, '自动出库 · 演示-李叔叔', stor_li);

  -- 编号序列：避免后续新建与演示编号冲突
  PERFORM setval(
    'storage_code_seq',
    GREATEST(
      COALESCE((SELECT MAX(CAST(SUBSTRING(code FROM 3) AS INTEGER)) FROM storage_records WHERE code ~ '^CZ[0-9]+$'), 0),
      90003
    ) + 1,
    false
  );
  PERFORM setval(
    'consumption_code_seq',
    GREATEST(
      COALESCE((SELECT MAX(CAST(SUBSTRING(code FROM 3) AS INTEGER)) FROM consumption_records WHERE code ~ '^XF[0-9]+$'), 0),
      90005
    ) + 1,
    false
  );
  PERFORM setval(
    'inventory_purchase_code_seq',
    GREATEST(
      COALESCE((SELECT MAX(CAST(SUBSTRING(code FROM 3) AS INTEGER)) FROM inventory_purchase_records WHERE code ~ '^JH[0-9]+$'), 0),
      90001
    ) + 1,
    false
  );

  RAISE NOTICE '演示数据写入完成：4 位客户、3 笔储值、5 笔消费、进货/补货/出库记录已就绪';
END $$;

COMMIT;

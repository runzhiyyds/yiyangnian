-- 客户改名时自动同步 storage_records.customer_name，避免违反外键
-- 将 storage_records(customer_name) -> customers(name) 的外键增加 ON UPDATE CASCADE

ALTER TABLE storage_records
  DROP CONSTRAINT IF EXISTS storage_records_customer_name_fkey;

ALTER TABLE storage_records
  ADD CONSTRAINT storage_records_customer_name_fkey
  FOREIGN KEY (customer_name) REFERENCES customers(name)
  ON DELETE CASCADE ON UPDATE CASCADE;

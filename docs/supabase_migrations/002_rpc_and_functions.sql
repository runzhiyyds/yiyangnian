-- 颐养年 - RPC 与函数
-- 储值编号生成：CZ00001
CREATE OR REPLACE FUNCTION generate_storage_code()
RETURNS TEXT AS $$
DECLARE
  next_val INT;
  code TEXT;
BEGIN
  next_val := nextval('storage_code_seq');
  code := 'CZ' || LPAD(next_val::TEXT, 5, '0');
  RETURN code;
END;
$$ LANGUAGE plpgsql;

-- 消费编号生成：XF00001
CREATE OR REPLACE FUNCTION generate_consumption_code()
RETURNS TEXT AS $$
DECLARE
  next_val INT;
  code TEXT;
BEGIN
  next_val := nextval('consumption_code_seq');
  code := 'XF' || LPAD(next_val::TEXT, 5, '0');
  RETURN code;
END;
$$ LANGUAGE plpgsql;

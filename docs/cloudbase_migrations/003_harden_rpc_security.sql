BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

ALTER FUNCTION generate_storage_code() SECURITY INVOKER;
ALTER FUNCTION generate_consumption_code() SECURITY INVOKER;
ALTER FUNCTION generate_inventory_purchase_code() SECURITY INVOKER;
ALTER FUNCTION initialize_current_account() SECURITY INVOKER;
ALTER FUNCTION release_push_device(text) SECURITY INVOKER;

CREATE OR REPLACE FUNCTION claim_push_device(
  p_device_token text,
  p_platform text DEFAULT 'android'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner text := auth.uid();
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated'
    OR v_owner IS NULL
    OR btrim(v_owner) = '' THEN
    RAISE EXCEPTION '未登录，无法绑定推送设备';
  END IF;
  IF p_device_token IS NULL OR btrim(p_device_token) = '' THEN
    RAISE EXCEPTION '设备 Token 不能为空';
  END IF;

  INSERT INTO push_devices (owner_id, device_token, platform, is_active)
  VALUES (v_owner, p_device_token, COALESCE(NULLIF(btrim(p_platform), ''), 'android'), true)
  ON CONFLICT (device_token) DO UPDATE
  SET owner_id = excluded.owner_id,
      platform = excluded.platform,
      is_active = true;
END;
$$;

REVOKE ALL ON FUNCTION claim_push_device(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION claim_push_device(text, text) TO authenticated;

COMMIT;

#!/bin/bash
# 从 env.json 生成 lib/core/env_generated.dart，避免 Release 下 dart-define 传值异常
set -e
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_JSON="$APP_DIR/env.json"
OUT="$APP_DIR/lib/core/env_generated.dart"
TEMPLATE="$APP_DIR/lib/core/env_generated.dart.template"

if [ ! -f "$ENV_JSON" ]; then
  echo "env.json 不存在，使用占位"
  cp "$TEMPLATE" "$OUT"
  exit 0
fi

# 用 node 或 python 解析 JSON 并转义（避免 shell 转义复杂）
if command -v node &>/dev/null; then
  SUPABASE_URL=$(node -e "console.log(require('$ENV_JSON').SUPABASE_URL || 'https://REPLACE_ME.supabase.co')")
  SUPABASE_ANON_KEY=$(node -e "var j=require('$ENV_JSON'); console.log((j.SUPABASE_ANON_KEY||'REPLACE_ME').replace(/'/g,\"\\\\'\"))")
  CLOUDBASE_ENV_ID=$(node -e "console.log(require('$ENV_JSON').CLOUDBASE_ENV_ID || 'yiyangnian-shanghai-d0b1453112fa')")
  UPDATE_CHECK_URL=$(node -e "console.log(require('$ENV_JSON').UPDATE_CHECK_URL || '')")
  PGYER_APP_KEY=$(node -e "console.log(require('$ENV_JSON').PGYER_APP_KEY || '')")
  PGYER_API_KEY=$(node -e "var j=require('$ENV_JSON'); console.log((j.PGYER_API_KEY||'').replace(/'/g,\"\\\\'\"))")
elif command -v python3 &>/dev/null; then
  SUPABASE_URL=$(python3 -c "
import json
with open('$ENV_JSON') as f: j=json.load(f)
print(j.get('SUPABASE_URL','https://REPLACE_ME.supabase.co'))
")
  SUPABASE_ANON_KEY=$(python3 -c "
import json
with open('$ENV_JSON') as f: j=json.load(f)
print((j.get('SUPABASE_ANON_KEY','REPLACE_ME')).replace(\"'\", \"\\\\'\"))
")
  CLOUDBASE_ENV_ID=$(python3 -c "
import json
with open('$ENV_JSON') as f: j=json.load(f)
print(j.get('CLOUDBASE_ENV_ID','yiyangnian-shanghai-d0b1453112fa'))
")
  UPDATE_CHECK_URL=$(python3 -c "
import json
with open('$ENV_JSON') as f: j=json.load(f)
print(j.get('UPDATE_CHECK_URL',''))
")
  PGYER_APP_KEY=$(python3 -c "
import json
with open('$ENV_JSON') as f: j=json.load(f)
print(j.get('PGYER_APP_KEY',''))
")
  PGYER_API_KEY=$(python3 -c "
import json
with open('$ENV_JSON') as f: j=json.load(f)
print((j.get('PGYER_API_KEY','')).replace(\"'\", \"\\\\'\"))
")
else
  echo "需要 node 或 python3 以解析 env.json"
  cp "$TEMPLATE" "$OUT"
  exit 0
fi

cat > "$OUT" << EOF
// 由 scripts/generate_env_dart.sh 从 env.json 生成，请勿手改
const String kSupabaseUrl = '$SUPABASE_URL';
const String kSupabaseAnonKey = '$SUPABASE_ANON_KEY';
const String kCloudBaseEnvId = '$CLOUDBASE_ENV_ID';
const String kUpdateCheckUrl = '$UPDATE_CHECK_URL';
const String kPgyerAppKey = '$PGYER_APP_KEY';
const String kPgyerApiKey = '$PGYER_API_KEY';
EOF
echo "已生成 $OUT"

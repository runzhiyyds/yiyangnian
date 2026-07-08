#!/usr/bin/env bash
# 颐养年店铺管理 - 使用 env.json 配置运行（与发布包完全一致：先生成 env_generated.dart 再运行）
# 在 app 目录执行：./scripts/run_with_env.sh [web|web-fast|android]

set -e
cd "$(dirname "$0")/.."

if [ ! -f "env.json" ]; then
  echo "未找到 env.json。请先复制 env.json.example 为 env.json 并填写 Supabase 配置。"
  echo "  cp env.json.example env.json"
  exit 1
fi

# 与发布脚本一致：从 env.json 生成 env_generated.dart 后再运行，保证本地与发布包配置来源相同
if [ -f "scripts/generate_env_dart.sh" ]; then
  chmod +x scripts/generate_env_dart.sh 2>/dev/null || true
  ./scripts/generate_env_dart.sh
  if grep -q "REPLACE_ME" lib/core/env_generated.dart 2>/dev/null; then
    echo "❌ env_generated.dart 仍含 REPLACE_ME，请检查 env.json 并确保已安装 node 或 python3"
    exit 1
  fi
fi

TARGET="${1:-web}"
echo "使用 env_generated.dart 配置运行到: $TARGET（与发布包一致）"
echo "  (可选: web | web-fast | android)"
echo ""

case "$TARGET" in
  web)
    flutter run -d chrome
    ;;
  web-fast)
    echo "使用 release 模式（启动快，无热重载）"
    flutter run -d chrome --release
    ;;
  android)
    ANDROID_ID=$(flutter devices --machine 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for x in d:
        if x.get('targetPlatform','').startswith('android'):
            print(x['id'])
            break
except: pass
" 2>/dev/null)
    if [ -z "$ANDROID_ID" ]; then
      echo "未找到 Android 设备。请用 USB 连接手机并开启 USB 调试。"
      echo "运行 'flutter devices' 查看可用设备。"
      exit 1
    fi
    echo "使用 Android 设备: $ANDROID_ID"
    flutter run -d "$ANDROID_ID"
    ;;
  *)
    echo "未知目标: $TARGET"
    echo "支持: web | web-fast | android"
    exit 1
    ;;
esac

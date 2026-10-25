#!/bin/bash

# 颐养年店铺管理 - 版本发布脚本（蒲公英）
# 使用方法: ./publish_new_version.sh [版本号] [更新说明]
# 发布前请配置:
#   1. 蒲公英 API Key：复制 pgyer_config.sh.example 为 pgyer_config.sh，填入 API Key
#      获取地址：https://www.pgyer.com/account/api
#   2. 在 app/env.json 中添加 UPDATE_CHECK_URL（version.json 的完整 URL）

# 加载蒲公英配置（若存在）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/pgyer_config.sh" ]; then
  source "$SCRIPT_DIR/pgyer_config.sh"
fi

VERSION=${1:-"1.0.1"}
RELEASE_NOTE=${2:-"修复问题和性能优化"}
APP_NAME="颐养年店铺管理"
APP_DIR="$(cd "$(dirname "$0")/app" && pwd)"

echo "🚀 开始发布 ${APP_NAME} v${VERSION}..."

# 步骤1: 更新版本号并构建 APK
echo "📝 步骤1: 更新版本号到 ${VERSION}..."
cd "$APP_DIR"

# 更新 pubspec.yaml 版本号（build number 用时间戳）
sed -i '' "s/version: .*/version: ${VERSION}+$(date +%s)/" pubspec.yaml

echo "🧹 清理项目..."
rm -rf "$APP_DIR/build" 2>/dev/null || true
flutter clean
flutter pub get

echo "🔨 构建 Release APK（移除调试引擎、调试内核和 DEBUG 标识）..."
if [ -f "env.json" ]; then
  if grep -q "REPLACE_ME" env.json 2>/dev/null; then
    echo "❌ env.json 中仍包含 REPLACE_ME，请先填写 SUPABASE_URL 和 SUPABASE_ANON_KEY 后再发布"
    exit 1
  fi
  echo "📌 从 env.json 生成 env_generated.dart（与 run_android.sh 相同）"
  if [ -f "scripts/generate_env_dart.sh" ]; then
    chmod +x scripts/generate_env_dart.sh 2>/dev/null || true
    ./scripts/generate_env_dart.sh
    if grep -q "REPLACE_ME" lib/core/env_generated.dart 2>/dev/null; then
      echo "❌ 生成失败：env_generated.dart 仍含 REPLACE_ME。请确认已安装 node 或 python3，且 env.json 格式正确"
      exit 1
    fi
    echo "  已生成: $(grep -o "kSupabaseUrl = '[^']*'" lib/core/env_generated.dart | head -1 | cut -c1-50)..."
  fi
  echo "📌 构建 Release APK（Android 主清单已显式声明 INTERNET 权限）"
  flutter build apk --release
else
  echo "❌ 未找到 app/env.json，无法构建可连接服务器的发布包。请先配置 env.json 后再发布。"
  exit 1
fi

if [ $? -ne 0 ]; then
    echo "❌ APK 构建失败，请检查错误信息"
    exit 1
fi

echo "✅ APK 构建成功！"
APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
SIZE=$(du -h "$APK_PATH" | cut -f1)

echo ""
echo "🎉 版本构建完成！"
echo "📱 新版本: v${VERSION}"
echo "📦 文件大小: ${SIZE}"
echo "📝 更新说明: ${RELEASE_NOTE}"
echo ""

# 自动上传到蒲公英（若已配置 PGYER_API_KEY）
if [ -n "$PGYER_API_KEY" ]; then
  echo "📤 正在上传 Release APK 到蒲公英（文件大小 ${SIZE}）..."
  # 使用 api.pgyer.com（官方 API 域名），非 www.pgyer.com；大文件需延长超时
  UPLOAD_RESULT=$(curl -s --connect-timeout 30 --max-time 600 -F "file=@$APK_PATH" -F "_api_key=$PGYER_API_KEY" -F "buildUpdateDescription=${RELEASE_NOTE}" "https://api.pgyer.com/apiv2/app/upload")
  SHORTCUT=$(echo "$UPLOAD_RESULT" | grep -o '"buildShortcutUrl":"[^"]*"' | cut -d'"' -f4)
  if [ -n "$SHORTCUT" ]; then
    echo "✅ 上传成功！"
    echo "📲 下载链接: https://www.pgyer.com/${SHORTCUT}"
    echo ""
    echo "  请将上述链接配置到 version.json 的 download_page_url 或 android_url。"
    echo "  将 version.json 部署到可访问的 URL，并在 env.json 中设置 UPDATE_CHECK_URL 指向该地址。"
  else
    echo "❌ 上传失败，请检查 API Key 或网络。"
    echo "  响应: $UPLOAD_RESULT"
    echo ""
    echo "  可手动上传: 打开 https://www.pgyer.com 上传 APK: $APK_PATH"
  fi
else
  echo "📋 下一步 - 上传到蒲公英:"
  echo "  1. 配置 API Key：复制 pgyer_config.sh.example 为 pgyer_config.sh，填入 API Key 后重新运行本脚本即可自动上传"
  echo "     获取地址：https://www.pgyer.com/account/api"
  echo ""
  echo "  2. 或手动上传：打开 https://www.pgyer.com，登录后上传 APK: $APK_PATH"
  echo "     版本说明: ${RELEASE_NOTE}"
  echo ""
  echo "  上传完成后，在蒲公英应用详情页获取下载链接，配置到 version.json 的 download_page_url 或 android_url。"
  echo "  将 version.json 部署到可访问的 URL，并在 env.json 中设置 UPDATE_CHECK_URL 指向该地址。"
fi

# 恢复 env_generated.dart 为占位，避免误提交真实密钥（APK 已编译完成，配置已打进包内）
if [ -f "$APP_DIR/lib/core/env_generated.dart.template" ]; then
  cp "$APP_DIR/lib/core/env_generated.dart.template" "$APP_DIR/lib/core/env_generated.dart"
  echo ""
  echo "📌 已恢复 env_generated.dart 为占位模板（下次调试前请再运行 run_android.sh / run_web.sh，会重新生成）"
fi

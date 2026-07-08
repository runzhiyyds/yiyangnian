#!/usr/bin/env bash
# 从项目根目录运行 Android：先进入 app 再执行 run_with_env.sh
cd "$(dirname "$0")/app" && ./scripts/run_with_env.sh android

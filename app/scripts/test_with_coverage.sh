#!/usr/bin/env bash
# 运行单元/组件测试并生成覆盖率报告
# 用法: ./scripts/test_with_coverage.sh
# 覆盖率输出: coverage/lcov.info，可用 genhtml 或 IDE 查看
set -e
cd "$(dirname "$0")/.."
flutter test --coverage
mkdir -p coverage
if [ -f coverage/lcov.info ]; then
  echo "Coverage written to coverage/lcov.info"
  # 可选：安装 lcov 后生成 HTML: genhtml coverage/lcov.info -o coverage/html
fi

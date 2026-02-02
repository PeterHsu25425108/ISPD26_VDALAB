#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 run.sh <input_dir> <platform_dir> <output_dir> <top_module>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 把參數原封不動交給你的工具
exec "$SCRIPT_DIR/solver" "$@"

#!/bin/bash
# generate-graph.sh — 从 WBS Ledger 生成 Mermaid 依赖关系图
# Usage: bash scripts/generate-graph.sh docs/spm/ledger.md

set -e

LEDGER="${1:-docs/spm/ledger.md}"

if [[ ! -f "$LEDGER" ]]; then
  echo "❌ Ledger not found: $LEDGER"
  exit 1
fi

echo "🔍 Generating dependency graph from: $LEDGER"
echo ""

# 提取任务列表：ID | Work Package | Dependencies
echo '```mermaid'
echo 'graph LR'

grep -E '^\|[[:space:]]*[0-9]+' "$LEDGER" | while IFS='|' read -r _ id wp deps rest; do
  id=$(echo "$id" | tr -d ' ')
  wp=$(echo "$wp" | xargs)  # trim
  deps=$(echo "$deps" | tr -d ' ')

  # 截断过长的工作包描述
  if [[ ${#wp} -gt 30 ]]; then
    wp="${wp:0:27}..."
  fi

  # 转义特殊字符
  wp="${wp//\"/\\\"}"
  wp="${wp//\(/ }"
  wp="${wp//\)/ }"

  echo "  T$id[\"$wp\"]"

  if [[ "$deps" != "-" && -n "$deps" ]]; then
    # 支持逗号分隔和空格分隔
    for dep in $(echo "$deps" | tr ',' ' '); do
      dep=$(echo "$dep" | tr -d ' ')
      if [[ -n "$dep" ]]; then
        echo "  T$dep --> T$id"
      fi
    done
  fi
done

echo '```'
echo ""
echo "✅ Copy the output above into any Markdown file or Mermaid Live Editor (https://mermaid.live)."
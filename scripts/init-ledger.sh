#!/bin/bash
# init-ledger.sh — 初始化 WBS ledger 文件
# Usage: bash scripts/init-ledger.sh [project_name] [output_path]

set -e

PROJECT_NAME="${1:-My Project}"
OUTPUT_DIR="${2:-docs/spm}"
OUTPUT_FILE="${OUTPUT_DIR}/ledger.md"

# 检查模板存在
# 模板路径：基于脚本所在目录定位，不依赖 cwd
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/wbs-ledger.md"
if [[ ! -f "$TEMPLATE" ]]; then
  echo "❌ Template not found: $TEMPLATE"
  exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 复制模板
cp "$TEMPLATE" "$OUTPUT_FILE"

# 替换标题
# 替换标题（中英文项目名占位符都匹配）
sed -i '' "s/\[项目名称\]/$PROJECT_NAME/g; s/\[Project Name\]/$PROJECT_NAME/g" "$OUTPUT_FILE" 2>/dev/null || sed -i "s/\[项目名称\]/$PROJECT_NAME/g; s/\[Project Name\]/$PROJECT_NAME/g" "$OUTPUT_FILE"

# 生成时间戳
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
sed -i '' "s/{TIMESTAMP}/$TIMESTAMP/g" "$OUTPUT_FILE" 2>/dev/null || sed -i "s/{TIMESTAMP}/$TIMESTAMP/g" "$OUTPUT_FILE"

# 生成初始任务
cat >> "$OUTPUT_FILE" << 'EOF'

## WBS 任务分解

| ID | Work Package | Dependencies | Context Brief | Exit Criteria | Evidence | Status |
|----|-------------|--------------|---------------|---------------|----------|--------|
| 1  | Project initialization | - | Cold-start: create project scaffold, init git, install deps | Scaffold created, deps installed, git init done | `ls -la`, `git status` | todo |
EOF

echo "✅ WBS ledger initialized:"
echo "   Location: $OUTPUT_FILE"
echo ""
echo "📝 Next steps:"
echo "   1. Edit ledger, fill in Task Summary section"
echo "   2. Add more tasks under WBS"
echo "   3. Run: bash scripts/attest-ledger.sh $OUTPUT_FILE"
echo ""
echo "🔍 Verify ledger integrity:"
echo "   bash scripts/verify-ledger.sh $OUTPUT_FILE"

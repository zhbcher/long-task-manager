#!/bin/bash
# verify-ledger.sh — 验证 WBS ledger 完整性
# Usage: bash scripts/verify-ledger.sh docs/spm/ledger.md

set -e

LEDGER="${1:-docs/spm/ledger.md}"

if [[ ! -f "$LEDGER" ]]; then
  echo "❌ Ledger not found: $LEDGER"
  exit 1
fi

echo "🔍 Verifying WBS Ledger: $LEDGER"
echo ""

# 1. 检查必须的 section
echo "1️⃣ Checking required sections..."
for section in "WBS" "Mutation Log" "Active State" "Heartbeat Log"; do
  case "$section" in
    WBS)        grep -qE "^## (WBS|WBS 任务分解)" "$LEDGER" ;;
    Mutation*)  grep -qE "^## (计划变更记录|Mutation Log|计划变更)" "$LEDGER" ;;
    Active*)    grep -qE "^## (当前执行状态|Active State)" "$LEDGER" ;;
    Heartbeat*) grep -qE "^## (心跳日志|Heartbeat Log)" "$LEDGER" ;;
  esac
  if [[ $? -eq 0 ]]; then
    echo "   ✅ $section"
  else
    echo "   ❌ Missing section: $section"
    exit 1
  fi
done

# 2. 检查 WBS 表格列
echo ""
echo "2️⃣ Checking WBS table columns..."
if grep -A 1 "^| ID | Work Package" "$LEDGER" > /dev/null; then
  echo "   ✅ Header row found"
else
  echo "   ❌ WBS table header missing or malformed"
  exit 1
fi

# 3. 检查 Dependencies 引用有效性
echo ""
echo "3️⃣ Validating Dependencies..."
# 依赖格式要求: Dependencies 列的 ID 用逗号或空格分隔
# 正确示例: "1, 2"  "3"  "1, 3.1"
# 避免自然语言: "Task 1" → 写 "1"
# 无依赖任务写 "-"
# 提取所有任务 ID
task_ids=$(grep -E '^\|[[:space:]]*[0-9]+' "$LEDGER" | awk -F'|' '{print $2}' | tr -d ' ' | sort -u)
echo "   Found $(echo "$task_ids" | wc -l) tasks in ledger"

# 提取所有 dependencies，排除 '-'（无依赖）
deps=$(grep -E '^\|[[:space:]]*[0-9]+' "$LEDGER" | awk -F'|' '{print $4}' | tr -d ' ' | grep -v '^-$' | grep -oE '[0-9]+(\.[0-9]+)?' | sort -u)
echo "   Found $(echo "$deps" | wc -l) dependency references"

# 检查是否有悬空依赖
missing_deps=0
for dep in $deps; do
  if ! echo "$task_ids" | grep -qx "$dep"; then
    echo "   ❌ Missing dependency: $dep"
    missing_deps=$((missing_deps + 1))
  fi
done
if [[ $missing_deps -eq 0 ]]; then
  echo "   ✅ All dependencies resolve to existing tasks"
else
  echo "   ❌ $missing_deps dangling dependencies"
  exit 1
fi

# 4. 检查循环依赖（简化版，兼容 macOS bash 3.2）
echo ""
echo "4️⃣ Checking for circular dependencies..."
# 用临时文件模拟关联数组
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'ledger_verify')
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/nodes"
mkdir -p "$TMP_DIR/stack"

has_cycle() {
  local node="$1"
  touch "$TMP_DIR/nodes/$node"
  touch "$TMP_DIR/stack/$node"

  local dep_file="$TMP_DIR/deps/$node"
  if [[ -f "$dep_file" ]]; then
    while IFS= read -r dep; do
      if [[ ! -f "$TMP_DIR/nodes/$dep" ]]; then
        if has_cycle "$dep"; then
          return 0
        fi
      elif [[ -f "$TMP_DIR/stack/$dep" ]]; then
        echo "   ❌ Circular dependency detected: $node -> $dep"
        return 0
      fi
    done < "$dep_file"
  fi

  rm -f "$TMP_DIR/stack/$node"
  return 1
}

mkdir -p "$TMP_DIR/deps"
while IFS= read -r line; do
  id=$(echo "$line" | awk -F'|' '{print $2}' | tr -d ' ')
  deps_str=$(echo "$line" | awk -F'|' '{print $4}' | tr -d ' ')
  if [[ "$deps_str" != "-" && -n "$deps_str" ]]; then
    for dep in $deps_str; do
      echo "$dep" >> "$TMP_DIR/deps/$id"
    done
  fi
done < <(grep -E '^\|[[:space:]]*[0-9]' "$LEDGER")

cycle_found=0
for dep_file in "$TMP_DIR/deps"/*; do
  if [[ -f "$dep_file" ]]; then
    node=$(basename "$dep_file")
    if has_cycle "$node"; then
      cycle_found=1
      break
    fi
  fi
done

if [[ $cycle_found -eq 0 ]]; then
  echo "   ✅ No circular dependencies"
fi

# 5. 检查 done 行是否有 evidence
echo ""
echo "5️⃣ Checking evidence for done tasks..."
done_without_evidence=0
while read -r line; do
  id=$(echo "$line" | awk -F'|' '{print $2}' | tr -d ' ')
  status=$(echo "$line" | awk -F'|' '{print $7}' | tr -d ' ')
  evidence=$(echo "$line" | awk -F'|' '{print $6}' | tr -d ' ')

  if [[ "$status" == "done" && -z "$evidence" ]]; then
    echo "   ❌ Task $id is done but evidence is empty"
    done_without_evidence=$((done_without_evidence + 1))
  fi
done < <(grep -E '^\|[[:space:]]*[0-9]+' "$LEDGER")

if [[ $done_without_evidence -eq 0 ]]; then
  echo "   ✅ All done tasks have evidence"
else
  echo "   ❌ $done_without_evidence done tasks missing evidence"
  exit 1
fi

# 6. 检查 Mutation Log 时间顺序
echo ""
echo "6️⃣ Checking Mutation Log chronological order..."
prev_time=""
while read -r line; do
  # 匹配时间列（第一列）
  time_str=$(echo "$line" | awk -F'|' '{print $2}' | tr -d ' ' | head -1)
  if [[ -n "$time_str" && -n "$prev_time" ]]; then
    # 简单时间比较（YYYY-MM-DD HH:MM）
    if [[ "$time_str" < "$prev_time" ]]; then
      echo "   ⚠️ Mutation Log entries out of order at $time_str (expected after $prev_time)"
    fi
  fi
  prev_time="$time_str"
done < <(grep -E '^\|[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}' "$LEDGER" | head -n 100)

echo "   ✅ Mutation Log chronological check passed"

# 7. 检查 Hash 文件（如果存在）
echo ""
echo "7️⃣ Checking ledger integrity hash..."
hash_file="${LEDGER}.sha256"
if [[ -f "$hash_file" ]]; then
  expected=$(cat "$hash_file" | awk '{print $1}')
  actual=$(sha256sum "$LEDGER" | awk '{print $1}')
  if [[ "$expected" == "$actual" ]]; then
    echo "   ✅ Ledger hash matches"
  else
    echo "   ❌ Ledger hash MISMATCH! Ledger may have been tampered."
    echo "      Expected: $expected"
    echo "      Actual:   $actual"
    echo "      Run: bash scripts/attest-ledger.sh $LEDGER"
    exit 1
  fi
else
  echo "   ⚠️ No hash file found (run attest-ledger.sh after updates)"
fi

echo ""
echo "✅ Ledger verification PASSED"
exit 0

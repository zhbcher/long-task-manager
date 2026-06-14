#!/bin/bash
# attest-ledger.sh — 生成 WBS ledger 的 SHA-256 哈希，保护完整性
# Usage: bash scripts/attest-ledger.sh [ledger_path]

set -e

LEDGER="${1:-docs/spm/ledger.md}"

if [[ ! -f "$LEDGER" ]]; then
  echo "❌ Ledger not found: $LEDGER"
  exit 1
fi

# 计算哈希（兼容 Linux/macOS）
HASH_FILE="${LEDGER}.sha256"
if command -v sha256sum &>/dev/null; then
  sha256sum "$LEDGER" > "$HASH_FILE"
elif command -v shasum &>/dev/null; then
  shasum -a 256 "$LEDGER" > "$HASH_FILE"
else
  echo "❌ No SHA-256 tool found (tried sha256sum, shasum)"
  exit 1
fi

echo "✅ Ledger hash attested:"
echo "   File: $LEDGER"
echo "   Hash: $(cat $HASH_FILE | awk '{print $1}')"
echo "   Saved to: $HASH_FILE"
echo ""
echo "⚠️  Remember to commit both files:"
echo "   git add $LEDGER $HASH_FILE"

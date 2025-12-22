#!/bin/bash
# Quick script to check UTXO confirmation status

ADDRESS="tb1pzwhfatdwel88smwamph5z6wsskets9x2th3l2jxu27waz4jgzy7s7uh4fx"

echo "=== Checking UTXO Status ==="
echo "Address: $ADDRESS"
echo ""

utxos=$(curl -s "https://mempool.space/testnet4/api/address/$ADDRESS/utxo")

if [ -z "$utxos" ] || [ "$utxos" = "[]" ]; then
    echo "❌ No UTXOs found"
    exit 1
fi

echo "UTXOs:"
echo "$utxos" | jq -r '.[] | "  \(.txid):\(.vout) - \(.value) sats - confirmed: \(.status.confirmed // false) - block: \(.status.block_height // "pending")"'

echo ""
confirmed_count=$(echo "$utxos" | jq '[.[] | select(.status.confirmed == true)] | length')
total_count=$(echo "$utxos" | jq 'length')

echo "Summary: $confirmed_count/$total_count UTXO(s) confirmed"

if [ "$total_count" -lt 2 ]; then
    echo ""
    echo "⚠️  Need at least 2 UTXOs for vault creation"
    echo "   - One for vault input"
    echo "   - One for funding/fees"
fi

if [ "$confirmed_count" -ge 2 ]; then
    echo ""
    echo "✅ Ready to create vault! Run: ./create-vault.sh"
fi


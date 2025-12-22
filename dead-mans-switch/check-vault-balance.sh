#!/bin/bash
# Check vault balance by querying the vault UTXO

set -e

cd "$(dirname "$0")"

echo "=== Checking Vault Balance ==="
echo ""

# Find most recent vault
VAULT_DIR=""
if [ -d "../vault-data" ]; then
    latest_vault=$(ls -td ../vault-data/vault-* 2>/dev/null | head -1)
    if [ -n "$latest_vault" ] && [ -f "$latest_vault/info.json" ]; then
        VAULT_DIR="$latest_vault"
    fi
fi

if [ -z "$VAULT_DIR" ]; then
    echo "❌ No vault found in vault-data directory"
    echo ""
    echo "Usage: $0 [vault-id]"
    echo "   Or: Set VAULT_DIR environment variable"
    exit 1
fi

echo "📋 Vault: $(basename "$VAULT_DIR")"
echo ""

vault_utxo=$(jq -r '.vault_utxo' "$VAULT_DIR/info.json")
app_id=$(jq -r '.app_id' "$VAULT_DIR/info.json")
owner_address=$(jq -r '.owner_address' "$VAULT_DIR/info.json")
beneficiary_address=$(jq -r '.beneficiary_address' "$VAULT_DIR/info.json")

if [ "$vault_utxo" = "TBD" ] || [ "$vault_utxo" = "null" ] || [ -z "$vault_utxo" ]; then
    echo "❌ Vault UTXO not set. Transaction may not be confirmed yet."
    exit 1
fi

echo "Vault UTXO: $vault_utxo"
echo ""

txid=$(echo "$vault_utxo" | cut -d':' -f1)
vout=$(echo "$vault_utxo" | cut -d':' -f2)

echo "Querying transaction: $txid"
tx_info=$(bitcoin-cli getrawtransaction "$txid" true 2>/dev/null | jq '.')

if [ -z "$tx_info" ] || [ "$tx_info" = "null" ]; then
    echo "❌ Transaction not found. It may not be confirmed yet."
    echo ""
    echo "You can check on a block explorer:"
    echo "  https://mempool.space/testnet4/tx/$txid"
    exit 1
fi

amount=$(echo "$tx_info" | jq -r ".vout[$vout].value")
amount_sats=$(echo "$tx_info" | jq -r ".vout[$vout].value * 100000000 | floor")
confirmations=$(echo "$tx_info" | jq -r '.confirmations // 0')

echo ""
echo "✅ Vault Balance:"
echo "   Amount: $amount BTC"
echo "   Amount: $amount_sats sats"
echo "   Confirmations: $confirmations"
echo ""
echo "Vault Details:"
echo "   App ID: $app_id"
echo "   Owner: $owner_address"
echo "   Beneficiary: $beneficiary_address"
echo ""
echo "Output Details:"
echo "$tx_info" | jq ".vout[$vout] | {
    value: .value,
    value_sats: (.value * 100000000 | floor),
    script_type: .scriptPubKey.type,
    address: .scriptPubKey.address
}"


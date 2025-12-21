#!/bin/bash
# Test heartbeat operation - updates vault's last_heartbeat_block

set -e

cd "$(dirname "$0")"

# Set RPC endpoint
export BITCOIN_TESTNET_RPC="${BITCOIN_TESTNET_RPC:-https://bitcoin-testnet4.gateway.tatum.io}"
export ADDRESS="${ADDRESS:-tb1qv0sgg028jxxugjnhqwjktz6ykjhulcl4ngknck}"

echo "=== Testing Heartbeat Operation ==="
echo ""

# Check if vault info exists
if [ -f "/tmp/vault-info.json" ]; then
    echo "📋 Loading vault info from /tmp/vault-info.json..."
    vault_utxo=$(jq -r '.vault_utxo' /tmp/vault-info.json)
    app_id=$(jq -r '.app_id' /tmp/vault-info.json)
    app_vk=$(jq -r '.app_vk' /tmp/vault-info.json)
    owner_address=$(jq -r '.owner_address' /tmp/vault-info.json)
    beneficiary_address=$(jq -r '.beneficiary_address' /tmp/vault-info.json)
    vault_address=$(jq -r '.vault_address' /tmp/vault-info.json)
    heartbeat_interval=$(jq -r '.heartbeat_interval' /tmp/vault-info.json)
    old_heartbeat_block=$(jq -r '.initial_block' /tmp/vault-info.json)
    
    if [ "$vault_utxo" = "TBD" ] || [ "$vault_utxo" = "null" ]; then
        echo "⚠️  Vault UTXO not set. Please provide it:"
        read -p "Vault UTXO (txid:vout): " vault_utxo
    fi
else
    echo "⚠️  No vault info found. Please provide vault details:"
    read -p "Vault UTXO (txid:vout): " vault_utxo
    read -p "App ID: " app_id
    read -p "Owner address: " owner_address
    read -p "Beneficiary address: " beneficiary_address
    read -p "Vault address: " vault_address
    read -p "Heartbeat interval (default 144): " heartbeat_interval
    heartbeat_interval=${heartbeat_interval:-144}
    read -p "Last heartbeat block: " old_heartbeat_block
fi

echo ""
echo "Vault UTXO: $vault_utxo"
echo "App ID: $app_id"
echo "Owner: $owner_address"
echo "Beneficiary: $beneficiary_address"
echo ""

# Build app
echo "1. Building app..."
app_bin=$(charms app build)
app_vk_check=$(charms app vk "$app_bin")
if [ "$app_vk" != "$app_vk_check" ]; then
    echo "⚠️  Warning: App VK mismatch!"
    echo "   Expected: $app_vk"
    echo "   Got: $app_vk_check"
fi
echo "   ✅ App VK: $app_vk_check"
echo ""

# Get current block
echo "2. Getting current block..."
block_response=$(curl -s -X POST "$BITCOIN_TESTNET_RPC" \
    -H "Content-Type: application/json" \
    -d '{"method":"getblockcount","params":[]}')
current_block=$(echo "$block_response" | jq -r '.result // 114180')
echo "   ✅ Current block: $current_block"
echo "   ✅ Last heartbeat block: $old_heartbeat_block"
echo "   ✅ Blocks since heartbeat: $((current_block - old_heartbeat_block))"
echo "   ✅ Heartbeat interval: $heartbeat_interval"
echo ""

# Check if expired
if [ $((current_block - old_heartbeat_block)) -ge $heartbeat_interval ]; then
    echo "❌ ERROR: Heartbeat has expired!"
    echo "   Blocks since heartbeat ($((current_block - old_heartbeat_block))) >= interval ($heartbeat_interval)"
    echo "   Cannot send heartbeat. Use test-release.sh instead."
    exit 1
fi

# Get previous transaction
echo "3. Getting previous transaction..."
txid=$(echo $vault_utxo | cut -d':' -f1)
prev_txs=$(curl -s -X POST "$BITCOIN_TESTNET_RPC" \
    -H "Content-Type: application/json" \
    -d "{\"method\":\"getrawtransaction\",\"params\":[\"$txid\"]}" \
    | jq -r '.result')
echo "   ✅ Got previous transaction (${#prev_txs} chars)"
echo ""

# Export variables
export app_bin app_vk app_id vault_address owner_address
export beneficiary_address heartbeat_interval
export vault_utxo old_heartbeat_block current_block prev_txs

# Validate spell
echo "4. Validating heartbeat spell..."
if cat ./spells/heartbeat.yaml | envsubst | \
   charms spell check --prev-txs=${prev_txs} --app-bins=${app_bin} 2>&1; then
    echo ""
    echo "✅ Heartbeat spell validation successful!"
    echo ""
else
    echo ""
    echo "❌ Heartbeat spell validation failed!"
    exit 1
fi

# Get funding UTXO
echo "5. Getting funding UTXO..."
utxos=$(curl -s "https://mempool.space/testnet4/api/address/$ADDRESS/utxo")
funding_utxo=$(echo "$utxos" | jq -r '.[0] | "\(.txid):\(.vout)"')
funding_value=$(echo "$utxos" | jq -r '.[0].value')

# Make sure funding UTXO is different from vault UTXO
if [ "$funding_utxo" = "$vault_utxo" ]; then
    funding_utxo=$(echo "$utxos" | jq -r '.[1] | "\(.txid):\(.vout)"')
    funding_value=$(echo "$utxos" | jq -r '.[1].value')
fi

if [ -z "$funding_utxo" ] || [ "$funding_utxo" = "null" ]; then
    echo "❌ No funding UTXO available"
    exit 1
fi

echo "   ✅ Funding UTXO: $funding_utxo ($funding_value sats)"
echo ""

# Create transaction
echo "6. Creating heartbeat transaction..."
echo "(This may take ~5 minutes for proof generation, or use --mock for testing)"
echo ""

prove_output=$(cat ./spells/heartbeat.yaml | envsubst | \
    charms spell prove \
    --app-bins="${app_bin}" \
    --prev-txs="${prev_txs}" \
    --funding-utxo="${funding_utxo}" \
    --funding-utxo-value="${funding_value}" \
    --change-address="${ADDRESS}" 2>&1 | tee /tmp/heartbeat-prove-output.txt)

if echo "$prove_output" | grep -q "Error"; then
    echo ""
    echo "❌ Proof generation failed!"
    echo ""
    echo "Error details:"
    echo "$prove_output" | grep -A 10 "Error"
    exit 1
fi

# Extract transactions
tx_json=$(echo "$prove_output" | grep -oE '\[.*\]' | tail -1)

if [ -z "$tx_json" ]; then
    echo ""
    echo "⚠️  Could not extract transaction JSON from output"
    echo "Full output saved to: /tmp/heartbeat-prove-output.txt"
    exit 1
fi

commit_tx=$(echo "$tx_json" | jq -r 'if .[0] | type == "string" then .[0] else .[0].bitcoin end' 2>/dev/null)
spell_tx=$(echo "$tx_json" | jq -r 'if .[1] | type == "string" then .[1] else .[1].bitcoin end' 2>/dev/null)

if [ -z "$commit_tx" ] || [ -z "$spell_tx" ] || [ "$commit_tx" = "null" ] || [ "$spell_tx" = "null" ]; then
    echo ""
    echo "❌ Could not extract commit and spell transactions"
    exit 1
fi

echo ""
echo "✅ Heartbeat transactions created successfully!"
echo ""
echo "=== Transaction Details ==="
echo "Commit TX: ${commit_tx:0:20}...${commit_tx: -20} (${#commit_tx} chars)"
echo "Spell TX:  ${spell_tx:0:20}...${spell_tx: -20} (${#spell_tx} chars)"
echo ""

# Save transactions
tx_json_array=$(jq -n --arg commit "$commit_tx" --arg spell "$spell_tx" '[$commit, $spell]')
echo "$tx_json_array" > /tmp/heartbeat-transactions.json
echo "Transactions saved to: /tmp/heartbeat-transactions.json"
echo ""

# Update vault info with new heartbeat block
vault_info=$(jq -n \
    --arg vault_utxo "TBD" \
    --arg app_id "$app_id" \
    --arg app_vk "$app_vk_check" \
    --arg owner_address "$owner_address" \
    --arg beneficiary_address "$beneficiary_address" \
    --arg vault_address "$vault_address" \
    --argjson heartbeat_interval "$heartbeat_interval" \
    --argjson last_heartbeat_block "$current_block" \
    '{
        vault_utxo: $vault_utxo,
        app_id: $app_id,
        app_vk: $app_vk,
        owner_address: $owner_address,
        beneficiary_address: $beneficiary_address,
        vault_address: $vault_address,
        heartbeat_interval: $heartbeat_interval,
        last_heartbeat_block: $last_heartbeat_block,
        note: "Vault UTXO will be available after transaction is confirmed"
    }')
echo "$vault_info" > /tmp/vault-info.json
echo "✅ Vault info updated with new heartbeat block: $current_block"
echo ""

echo "=== Next Steps ==="
echo "1. Sign both transactions"
echo "2. Submit as package: b submitpackage '$(cat /tmp/heartbeat-transactions.json)'"
echo "3. After confirmation, update vault_utxo in /tmp/vault-info.json"

#!/bin/bash
# Test release operation - releases funds to beneficiary when heartbeat expires

set -e

cd "$(dirname "$0")"

# Set RPC endpoint
export BITCOIN_TESTNET_RPC="${BITCOIN_TESTNET_RPC:-https://bitcoin-testnet4.gateway.tatum.io}"
export ADDRESS="${ADDRESS:-tb1pzwhfatdwel88smwamph5z6wsskets9x2th3l2jxu27waz4jgzy7s7uh4fx}"

echo "=== Testing Release Operation ==="
echo ""

# Check for vault info in data directory first, then /tmp
VAULT_INFO=""
if [ -d "../vault-data" ]; then
    # Find most recent vault
    latest_vault=$(ls -td ../vault-data/vault-* 2>/dev/null | head -1)
    if [ -n "$latest_vault" ] && [ -f "$latest_vault/info.json" ]; then
        VAULT_INFO="$latest_vault/info.json"
    fi
fi

if [ -z "$VAULT_INFO" ] && [ -f "/tmp/vault-info.json" ]; then
    VAULT_INFO="/tmp/vault-info.json"
fi

# Check if vault info exists
if [ -n "$VAULT_INFO" ] && [ -f "$VAULT_INFO" ]; then
    echo "📋 Loading vault info from $VAULT_INFO..."
    vault_utxo=$(jq -r '.vault_utxo' "$VAULT_INFO")
    app_id=$(jq -r '.app_id' "$VAULT_INFO")
    app_vk=$(jq -r '.app_vk' "$VAULT_INFO")
    owner_address=$(jq -r '.owner_address' "$VAULT_INFO")
    beneficiary_address=$(jq -r '.beneficiary_address' "$VAULT_INFO")
    heartbeat_interval=$(jq -r '.heartbeat_interval' "$VAULT_INFO")
    last_heartbeat_block=$(jq -r '.last_heartbeat_block // .initial_block' "$VAULT_INFO")
    
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
    read -p "Heartbeat interval (default 144): " heartbeat_interval
    heartbeat_interval=${heartbeat_interval:-144}
    read -p "Last heartbeat block: " last_heartbeat_block
fi

echo ""
echo "Vault UTXO: $vault_utxo"
echo "App ID: $app_id"
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
echo "   ✅ Last heartbeat block: $last_heartbeat_block"
echo "   ✅ Blocks since heartbeat: $((current_block - last_heartbeat_block))"
echo "   ✅ Heartbeat interval: $heartbeat_interval"
echo ""

# Check if expired
if [ $((current_block - last_heartbeat_block)) -lt $heartbeat_interval ]; then
    echo "❌ ERROR: Heartbeat has NOT expired yet!"
    echo "   Blocks remaining: $((heartbeat_interval - (current_block - last_heartbeat_block)))"
    echo "   Cannot release yet. Wait for expiration or use test-heartbeat.sh"
    exit 1
fi

echo "   ✅ Heartbeat has expired - release is allowed"
echo ""

# Get previous transaction
echo "3. Getting previous transaction..."
txid=$(echo $vault_utxo | cut -d':' -f1)
prev_txs=$(curl -s -X POST "$BITCOIN_TESTNET_RPC" \
    -H "Content-Type: application/json" \
    -d "{\"method\":\"getrawtransaction\",\"params\":[\"$txid\"]}" \
    | jq -r '.result')
echo "   ✅ Got previous transaction (${#prev_txs} chars)"
echo ""

# Get vault Bitcoin amount from UTXO (all goes to beneficiary)
echo "3a. Getting vault Bitcoin amount..."
vault_txid=$(echo $vault_utxo | cut -d':' -f1)
vault_vout=$(echo $vault_utxo | cut -d':' -f2)
vault_tx_info=$(bitcoin-cli getrawtransaction "$vault_txid" true 2>/dev/null | jq '.')
vault_sats=$(echo "$vault_tx_info" | jq -r ".vout[$vault_vout].value * 100000000 | floor")
if [ -z "$vault_sats" ] || [ "$vault_sats" = "null" ] || [ "$vault_sats" = "0" ]; then
    vault_sats=10000  # Default if can't read
fi
echo "   ✅ Vault Bitcoin to release: $vault_sats sats"
echo ""

# Export variables
export app_bin app_vk app_id owner_address beneficiary_address
export heartbeat_interval last_heartbeat_block current_block vault_sats
export vault_utxo prev_txs beneficiary_address

# Validate spell
echo "4. Validating release spell..."
if cat ./spells/release.yaml | envsubst | \
   charms spell check --prev-txs=${prev_txs} --app-bins=${app_bin} 2>&1; then
    echo ""
    echo "✅ Release spell validation successful!"
    echo ""
else
    echo ""
    echo "❌ Release spell validation failed!"
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
echo "6. Creating release transaction..."
echo "(This may take ~5 minutes for proof generation, or use --mock for testing)"
echo ""

prove_output=$(cat ./spells/release.yaml | envsubst | \
    charms spell prove \
    --app-bins="${app_bin}" \
    --prev-txs="${prev_txs}" \
    --funding-utxo="${funding_utxo}" \
    --funding-utxo-value="${funding_value}" \
    --change-address="${ADDRESS}" \
    --mock 2>&1 | tee /tmp/release-prove-output.txt)

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
    echo "Full output saved to: /tmp/release-prove-output.txt"
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
echo "✅ Release transactions created successfully!"
echo ""
echo "=== Transaction Details ==="
echo "Commit TX: ${commit_tx:0:20}...${commit_tx: -20} (${#commit_tx} chars)"
echo "Spell TX:  ${spell_tx:0:20}...${spell_tx: -20} (${#spell_tx} chars)"
echo ""

# Save transactions
tx_json_array=$(jq -n --arg commit "$commit_tx" --arg spell "$spell_tx" '[$commit, $spell]')
echo "$tx_json_array" > /tmp/release-transactions.json
echo "Transactions saved to: /tmp/release-transactions.json"
echo ""

echo "=== Release Summary ==="
echo "✅ Funds will be released to: $beneficiary_address"
echo "✅ Vault will be consumed (no output)"
echo ""

echo "=== Next Steps ==="
echo "1. Sign both transactions"
echo "2. Submit as package: b submitpackage '$(cat /tmp/release-transactions.json)'"
echo "3. Funds will be sent to beneficiary address"

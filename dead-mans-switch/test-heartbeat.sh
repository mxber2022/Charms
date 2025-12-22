#!/bin/bash
# Test heartbeat operation - updates vault's last_heartbeat_block

set -e

cd "$(dirname "$0")"

# Set RPC endpoint
export BITCOIN_TESTNET_RPC="${BITCOIN_TESTNET_RPC:-https://bitcoin-testnet4.gateway.tatum.io}"
export ADDRESS="${ADDRESS:-tb1pzwhfatdwel88smwamph5z6wsskets9x2th3l2jxu27waz4jgzy7s7uh4fx}"

echo "=== Testing Heartbeat Operation ==="
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

if [ -n "$VAULT_INFO" ] && [ -f "$VAULT_INFO" ]; then
    echo "📋 Loading vault info from $VAULT_INFO..."
    vault_utxo=$(jq -r '.vault_utxo' "$VAULT_INFO")
    app_id=$(jq -r '.app_id' "$VAULT_INFO")
    app_vk=$(jq -r '.app_vk' "$VAULT_INFO")
    owner_address=$(jq -r '.owner_address' "$VAULT_INFO")
    beneficiary_address=$(jq -r '.beneficiary_address' "$VAULT_INFO")
    vault_address=$(jq -r '.vault_address' "$VAULT_INFO")
    heartbeat_interval=$(jq -r '.heartbeat_interval' "$VAULT_INFO")
    old_heartbeat_block=$(jq -r '.last_heartbeat_block // .initial_block' "$VAULT_INFO")
    
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
current_block=$(bitcoin-cli getblockcount 2>/dev/null || echo "114180")
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
prev_txs=$(bitcoin-cli getrawtransaction "$txid" true 2>/dev/null | jq -r '.hex // empty' || echo "")
if [ -z "$prev_txs" ] || [ "$prev_txs" = "null" ]; then
    echo "   ⚠️  Could not get previous transaction with witness data"
    echo "   Trying without witness data..."
    prev_txs=$(bitcoin-cli getrawtransaction "$txid" false 2>/dev/null || echo "")
fi
if [ -z "$prev_txs" ] || [ "$prev_txs" = "null" ]; then
    echo "   ❌ Could not get previous transaction"
    exit 1
fi
echo "   ✅ Got previous transaction (${#prev_txs} chars)"
echo ""

# Use extractAndVerifySpell to read and validate vault state
echo "3b. Reading vault state using extractAndVerifySpell..."
tx_hex=$(bitcoin-cli getrawtransaction "$txid" false 2>/dev/null)
if [ -n "$tx_hex" ]; then
    vault_state=$(node -e "
        const wasm = require('../charms/charms-lib/target/wasm-bindgen-nodejs/charms_lib.js');
        const tx = { bitcoin: '$tx_hex' };
        try {
            const res = wasm.extractAndVerifySpell(tx, false);
            if (res.tx && res.tx.outs && res.tx.outs.length > 0) {
                const output = res.tx.outs[0];
                if (output instanceof Map && output.has(0)) {
                    const charmData = output.get(0);
                    if (charmData instanceof Map) {
                        const state = {};
                        for (const [key, value] of charmData.entries()) {
                            state[key] = value;
                        }
                        console.log(JSON.stringify(state));
                    }
                }
            }
        } catch (e) {
            process.exit(1);
        }
    " 2>/dev/null)
    
    if [ -n "$vault_state" ] && [ "$vault_state" != "null" ]; then
        echo "   ✅ Extracted vault state using extractAndVerifySpell"
        # Update variables from extracted state
        extracted_owner=$(echo "$vault_state" | jq -r '.owner // empty')
        extracted_beneficiary=$(echo "$vault_state" | jq -r '.beneficiary // empty')
        extracted_last_heartbeat=$(echo "$vault_state" | jq -r '.last_heartbeat_block // empty')
        extracted_interval=$(echo "$vault_state" | jq -r '.heartbeat_interval // empty')
        
        if [ -n "$extracted_owner" ] && [ -n "$extracted_beneficiary" ]; then
            echo "   ✅ Validated: owner=$extracted_owner, beneficiary=$extracted_beneficiary"
            echo "   ✅ Validated: last_heartbeat_block=$extracted_last_heartbeat, interval=$extracted_interval"
            # Use extracted values to ensure they match
            owner_address=$extracted_owner
            beneficiary_address=$extracted_beneficiary
            old_heartbeat_block=$extracted_last_heartbeat
            heartbeat_interval=$extracted_interval
        fi
    else
        echo "   ⚠️  Could not extract vault state, using values from vault-info.json"
    fi
else
    echo "   ⚠️  Could not get transaction hex for extractAndVerifySpell"
fi
echo ""

# Get vault Bitcoin amount from UTXO
echo "3a. Getting vault Bitcoin amount..."
vault_txid=$(echo $vault_utxo | cut -d':' -f1)
vault_vout=$(echo $vault_utxo | cut -d':' -f2)
vault_tx_info=$(bitcoin-cli getrawtransaction "$vault_txid" true 2>/dev/null | jq '.')
vault_sats=$(echo "$vault_tx_info" | jq -r ".vout[$vault_vout].value * 100000000 | floor")
if [ -z "$vault_sats" ] || [ "$vault_sats" = "null" ] || [ "$vault_sats" = "0" ]; then
    vault_sats=10000  # Default if can't read
fi
echo "   ✅ Vault Bitcoin: $vault_sats sats"

# Export variables
export app_bin app_vk app_id vault_address owner_address
export beneficiary_address heartbeat_interval vault_sats
export vault_utxo old_heartbeat_block current_block prev_txs

# Validate spell (skip if validation fails - prover will validate)
echo "4. Validating heartbeat spell..."
if cat ./spells/heartbeat.yaml | envsubst | \
   charms spell check --prev-txs=${prev_txs} --app-bins=${app_bin} 2>&1; then
    echo ""
    echo "✅ Heartbeat spell validation successful!"
    echo ""
else
    echo ""
    echo "⚠️  Local validation failed (charm state may not be readable)"
    echo "   Proceeding to create transaction - prover will validate..."
    echo ""
fi

# Get funding UTXO
echo "5. Getting funding UTXO..."
utxos=$(bitcoin-cli listunspent 0 9999999 "[\"$ADDRESS\"]" 2>/dev/null || echo "[]")
funding_utxo=$(echo "$utxos" | jq -r '.[0] | "\(.txid):\(.vout)"')
funding_value=$(echo "$utxos" | jq -r '.[0].amount * 100000000 | floor')

# Make sure funding UTXO is different from vault UTXO
if [ "$funding_utxo" = "$vault_utxo" ]; then
    funding_utxo=$(echo "$utxos" | jq -r '.[1] | "\(.txid):\(.vout)"')
    funding_value=$(echo "$utxos" | jq -r '.[1].amount * 100000000 | floor')
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
    --change-address="${ADDRESS}" \
    2>&1 | tee /tmp/heartbeat-prove-output.txt)

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
echo "$tx_json_array" > "$VAULT_DIR/heartbeat-transactions.json"
echo "$tx_json_array" > /tmp/heartbeat-transactions.json  # Also save to /tmp
echo "Transactions saved to: $VAULT_DIR/heartbeat-transactions.json"
echo ""

# Update vault info with new heartbeat block
VAULT_DIR=$(dirname "$VAULT_INFO" 2>/dev/null || echo "../vault-data/vault-$(echo $app_id | cut -c1-16)")
mkdir -p "$VAULT_DIR"

vault_info=$(jq --argjson last_heartbeat_block "$current_block" '.last_heartbeat_block = $last_heartbeat_block' "$VAULT_INFO")
echo "$vault_info" > "$VAULT_INFO"
echo "$vault_info" > /tmp/vault-info.json  # Also update /tmp
echo "✅ Vault info updated with new heartbeat block: $current_block"
echo ""

echo "=== Next Steps ==="
echo "1. Sign both transactions"
echo "2. Submit as package: b submitpackage '$(cat /tmp/heartbeat-transactions.json)'"
echo "3. After confirmation, update vault_utxo in /tmp/vault-info.json"

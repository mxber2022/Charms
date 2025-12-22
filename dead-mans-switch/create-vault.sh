#!/bin/bash
# Create Inheritance Vault on Bitcoin testnet

set -e

cd "$(dirname "$0")"

# Set RPC endpoint and credentials (Testnet4)
export BITCOIN_TESTNET_RPC="${BITCOIN_TESTNET_RPC:-https://bitcoin-testnet4.gateway.tatum.io}"
export ADDRESS="${ADDRESS:-tb1pzwhfatdwel88smwamph5z6wsskets9x2th3l2jxu27waz4jgzy7s7uh4fx}"
export PRIVATE_KEY="${PRIVATE_KEY:-76476027042ab81d77d4bbc63ef3ea722d2ac7f2f35f0844915da7c39ab5c72d}"

echo "=== Creating Inheritance Vault on Testnet ==="
echo "Address: $ADDRESS"
echo "RPC: $BITCOIN_TESTNET_RPC"
echo ""

# Build app
echo "1. Building app..."
app_bin=$(charms app build)
app_vk=$(charms app vk "$app_bin")
echo "   ✅ App VK: $app_vk"
echo ""

# Get UTXO from address using block explorer (Tatum RPC doesn't support listunspent)
echo "2. Getting UTXO from address..."
utxos=$(curl -s "https://mempool.space/testnet4/api/address/$ADDRESS/utxo")

utxo_count=$(echo "$utxos" | jq 'length')

if [ "$utxo_count" -eq 0 ] || [ "$utxo_count" = "null" ]; then
    echo "   ❌ No UTXOs found!"
    echo ""
    echo "   Get testnet funds from a testnet4 faucet"
    echo "   Your address: $ADDRESS"
    echo ""
    exit 1
fi

echo "   ✅ Found $utxo_count UTXO(s)"
first_utxo=$(echo "$utxos" | jq -r '.[0] | "\(.txid):\(.vout)"')
amount=$(echo "$utxos" | jq -r '.[0].value / 100000000')
echo "   Using: $first_utxo ($amount BTC)"
in_utxo=$first_utxo

# Calculate app_id
app_id=$(echo -n "${in_utxo}" | sha256sum | cut -d' ' -f1)
echo "   ✅ Vault Identity (app_id): $app_id"
echo ""

# Get addresses (use defaults)
echo "3. Setting addresses..."
owner_address=$ADDRESS
beneficiary_address=${BENEFICIARY_ADDRESS:-$ADDRESS}
vault_address=${VAULT_ADDRESS:-$ADDRESS}
echo "   ✅ Owner: $owner_address"
echo "   ✅ Beneficiary: $beneficiary_address"
echo "   ✅ Vault: $vault_address"

# Get current block
if command -v b &> /dev/null; then
    current_block=$(b getblockcount 2>/dev/null || echo "850000")
elif command -v get_block_count &> /dev/null; then
    current_block=$(get_block_count)
else
    current_block=$(curl -s -X POST "$BITCOIN_TESTNET_RPC" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"1.0","id":"test","method":"getblockcount","params":[]}' \
        | jq -r '.result' || echo "850000")
fi
echo "   ✅ Current block: $current_block"

# Heartbeat interval
heartbeat_interval=${HEARTBEAT_INTERVAL:-144}
echo "   ✅ Heartbeat interval: $heartbeat_interval blocks (~$((heartbeat_interval * 10 / 60 / 24)) days)"

# Vault Bitcoin amount (in sats)
vault_sats=${VAULT_SATS:-10000}  # Default 10,000 sats (0.0001 BTC)
echo "   ✅ Vault Bitcoin: $vault_sats sats ($(echo "scale=8; $vault_sats / 100000000" | bc) BTC)"

echo ""

# Get previous transaction
echo "4. Getting previous transaction..."
txid=$(echo $in_utxo | cut -d':' -f1)

if command -v b &> /dev/null; then
    prev_txs=$(b getrawtransaction $txid 2>/dev/null || echo "")
elif command -v get_raw_transaction &> /dev/null; then
    prev_txs=$(get_raw_transaction "$txid")
else
    prev_txs=$(curl -s -X POST "$BITCOIN_TESTNET_RPC" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"1.0\",\"id\":\"test\",\"method\":\"getrawtransaction\",\"params\":[\"$txid\"]}" \
        | jq -r '.result' || echo "")
fi

if [ -z "$prev_txs" ] || [ "$prev_txs" = "null" ]; then
    echo "   ⚠️  Could not get previous transaction"
    read -p "   Enter previous transaction hex: " prev_txs
else
    echo "   ✅ Got previous transaction (${#prev_txs} chars)"
fi

echo ""

# Export variables
export app_bin app_vk app_id vault_address owner_address
export beneficiary_address current_block heartbeat_interval
export in_utxo_0=$in_utxo prev_txs

# Validate spell
echo "5. Validating vault creation spell..."
if cat ./spells/create-vault.yaml | envsubst | \
   charms spell check --prev-txs=${prev_txs} --app-bins=${app_bin} 2>&1; then
    echo ""
    echo "✅ Spell validation successful!"
    echo ""
    echo "=== Vault Creation Details ==="
    echo "App VK: $app_vk"
    echo "Vault Identity: $app_id"
    echo "Owner: $owner_address"
    echo "Beneficiary: $beneficiary_address"
    echo "Heartbeat Interval: $heartbeat_interval blocks"
    echo "Initial Block: $current_block"
    echo ""
echo ""
echo "=== Creating Transaction ==="
# Get funding UTXO (must be different from input UTXO)
utxos=$(curl -s "https://mempool.space/testnet4/api/address/$ADDRESS/utxo")
utxo_count=$(echo "$utxos" | jq 'length')

# Find a UTXO different from the input UTXO
funding_utxo=""
funding_value=""
for i in $(seq 0 $((utxo_count - 1))); do
    candidate=$(echo "$utxos" | jq -r ".[$i] | \"\(.txid):\(.vout)\"")
    if [ "$candidate" != "$in_utxo" ]; then
        funding_utxo=$candidate
        funding_value=$(echo "$utxos" | jq -r ".[$i].value")
        break
    fi
done

if [ -z "$funding_utxo" ] || [ "$funding_utxo" = "null" ]; then
    echo "❌ Need at least 2 different UTXOs:"
    echo "   - One for the vault input"
    echo "   - One for funding/fees"
    echo ""
    echo "   Current UTXOs:"
    echo "$utxos" | jq -r '.[] | "  \(.txid):\(.vout) - \(.value) sats"'
    exit 1
fi

echo "Input UTXO: $in_utxo"
echo "Funding UTXO: $funding_utxo ($funding_value sats)"
echo ""

# Export all variables for envsubst (ensure current_block is exported)
export app_bin app_vk app_id vault_address owner_address
export beneficiary_address heartbeat_interval vault_sats
export in_utxo_0=$in_utxo
export current_block  # Make sure this is exported

echo "Creating transaction with charms spell prove..."
echo "(This may take ~5 minutes for proof generation)"
echo ""

# Use charms spell prove directly (as per documentation)
# Format: cat spell.yaml | envsubst | charms spell prove --app-bins=... --prev-txs=... --funding-utxo=... --funding-utxo-value=... --change-address=...
# Note: prev_txs should only include transactions for input UTXOs (spell inputs), not the funding UTXO
# The funding UTXO is handled separately via --funding-utxo parameter

prove_output=$(cat ./spells/create-vault.yaml | envsubst | \
    charms spell prove \
    --app-bins="${app_bin}" \
    --prev-txs="${prev_txs}" \
    --funding-utxo="${funding_utxo}" \
    --funding-utxo-value="${funding_value}" \
    --change-address="${ADDRESS}" 2>&1 | tee /tmp/prove-output.txt)

if echo "$prove_output" | grep -q "Error"; then
    echo ""
    echo "❌ Proof generation failed!"
    echo ""
    echo "Error details:"
    echo "$prove_output" | grep -A 10 "Error"
    echo ""
    if echo "$prove_output" | grep -q "duplicate funding UTXO"; then
        echo "⚠️  This error usually means:"
        echo "   1. The funding UTXO was already used in a previous transaction"
        echo "   2. The UTXO is unconfirmed from a pending transaction"
        echo ""
        echo "   Try:"
        echo "   - Wait for UTXO confirmations"
        echo "   - Use a different funding UTXO"
        echo "   - Check if previous transactions are pending"
    fi
    exit 1
fi

# Extract JSON array of transactions from output
# The output should contain a JSON array like: ["02000000...", "02000000..."]
# or [{"bitcoin":"02000000..."}, {"bitcoin":"02000000..."}]
tx_json=$(echo "$prove_output" | grep -oE '\[.*\]' | tail -1)

if [ -z "$tx_json" ]; then
    echo ""
    echo "⚠️  Could not extract transaction JSON from output"
    echo "Full output saved to: /tmp/prove-output.txt"
    echo ""
    echo "Please check the output manually for the transaction hexes"
    exit 1
fi

# Parse transactions (handle both formats: ["hex1", "hex2"] or [{"bitcoin":"hex1"}, {"bitcoin":"hex2"}])
commit_tx=$(echo "$tx_json" | jq -r 'if .[0] | type == "string" then .[0] else .[0].bitcoin end' 2>/dev/null)
spell_tx=$(echo "$tx_json" | jq -r 'if .[1] | type == "string" then .[1] else .[1].bitcoin end' 2>/dev/null)

if [ -z "$commit_tx" ] || [ -z "$spell_tx" ] || [ "$commit_tx" = "null" ] || [ "$spell_tx" = "null" ]; then
    echo ""
    echo "❌ Could not extract commit and spell transactions"
    echo "Output: $tx_json"
    exit 1
fi

echo ""
echo "✅ Transactions created successfully!"
echo ""
echo "=== Transaction Details ==="
echo "Commit TX: ${commit_tx:0:20}...${commit_tx: -20} (${#commit_tx} chars)"
echo "Spell TX:  ${spell_tx:0:20}...${spell_tx: -20} (${#spell_tx} chars)"
echo ""

# Create data directory
DATA_DIR="../vault-data"
mkdir -p "$DATA_DIR"
VAULT_ID="${app_id:0:16}"  # Use first 16 chars of app_id as vault ID
VAULT_DIR="$DATA_DIR/vault-$VAULT_ID"
mkdir -p "$VAULT_DIR"

# Save transactions in the format expected by submitpackage
tx_json_array=$(jq -n --arg commit "$commit_tx" --arg spell "$spell_tx" '[$commit, $spell]')
echo "$tx_json_array" > "$VAULT_DIR/transactions.json"
echo "$tx_json_array" > /tmp/vault-transactions.json  # Also save to /tmp for compatibility
echo "Transactions saved to: $VAULT_DIR/transactions.json"
echo ""

# Save vault details for heartbeat/release operations
vault_info=$(jq -n \
    --arg vault_utxo "TBD" \
    --arg app_id "$app_id" \
    --arg app_vk "$app_vk" \
    --arg owner_address "$owner_address" \
    --arg beneficiary_address "$beneficiary_address" \
    --arg vault_address "$vault_address" \
    --arg input_utxo "$in_utxo" \
    --argjson heartbeat_interval "$heartbeat_interval" \
    --argjson initial_block "$current_block" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
        vault_utxo: $vault_utxo,
        input_utxo: $input_utxo,
        app_id: $app_id,
        app_vk: $app_vk,
        owner_address: $owner_address,
        beneficiary_address: $beneficiary_address,
        vault_address: $vault_address,
        heartbeat_interval: $heartbeat_interval,
        initial_block: $initial_block,
        last_heartbeat_block: $initial_block,
        created_at: $created_at,
        note: "Vault UTXO will be available after transaction is confirmed"
    }')
echo "$vault_info" > "$VAULT_DIR/info.json"
echo "$vault_info" > /tmp/vault-info.json  # Also save to /tmp for compatibility
echo "Vault info saved to: $VAULT_DIR/info.json"
echo "   (Update vault_utxo after transaction is confirmed)"
echo ""

# Save commit and spell transactions separately
echo "$commit_tx" > "$VAULT_DIR/commit-tx.hex"
echo "$spell_tx" > "$VAULT_DIR/spell-tx.hex"
echo "Individual transactions saved:"
echo "  - $VAULT_DIR/commit-tx.hex"
echo "  - $VAULT_DIR/spell-tx.hex"
echo ""

# Sign transactions
echo "=== Signing Transactions ==="
if command -v b &> /dev/null; then
    # Using bitcoin-cli (if available)
    echo "Using bitcoin-cli to sign..."
    signed_txs="[]"
    while IFS= read -r tx_hex; do
        signed_tx=$(b signrawtransactionwithwallet "$tx_hex" 2>/dev/null | jq -r '.hex // empty')
        if [ -n "$signed_tx" ]; then
            signed_txs=$(echo "$signed_txs" | jq ". + [{\"bitcoin\":\"$signed_tx\"}]")
        fi
    done < <(echo "$tx_json" | jq -r '.[] | .bitcoin')
    
    if [ "$signed_txs" != "[]" ]; then
        echo "$signed_txs" > /tmp/vault-transactions-signed.json
        echo "✅ Signed transactions saved to: /tmp/vault-transactions-signed.json"
        echo ""
        echo "=== Ready to Submit ==="
        echo "Submit with:"
        echo "  b submitpackage '$(cat /tmp/vault-transactions-signed.json | jq -c 'map(.bitcoin)')'"
    else
        echo "⚠️  Could not sign with bitcoin-cli"
        echo "   You'll need to sign manually"
    fi
else
    echo "⚠️  bitcoin-cli not available (aliased as 'b')"
    echo "   You need to sign the transactions manually"
    echo ""
    echo "To sign and submit:"
    echo "1. Sign both transactions"
    echo "2. Submit as package: b submitpackage '[tx1_hex, tx2_hex]'"
fi

fi

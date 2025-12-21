#!/bin/bash
# Test script for Inheritance Vault operations

set -e

cd "$(dirname "$0")"

echo "=== Building Vault App ==="
app_bin=$(charms app build)
app_vk=$(charms app vk "$app_bin")
echo "App VK: $app_vk"
echo ""

# Base variables
export app_bin
export app_vk
export in_utxo_0="d8fa4cdade7ac3dff64047dc73b58591ebe638579881b200d4fea68fc84521f0:0"
export app_id=$(echo -n "${in_utxo_0}" | sha256sum | cut -d' ' -f1)
export vault_address="tb1p3w06fgh64axkj3uphn4t258ehweccm367vkdhkvz8qzdagjctm8qaw2xyv"
export owner_address="tb1qowner123456789012345678901234567890"
export beneficiary_address="tb1qbeneficiary123456789012345678901234"
export heartbeat_interval=144

# Example previous transaction (you'll need actual transaction data in production)
prev_txs=02000000000101a3a4c09a03f771e863517b8169ad6c08784d419e6421015e8c360db5231871eb0200000000fdffffff024331070000000000160014555a971f96c15bd5ef181a140138e3d3c960d6e1204e0000000000002251207c4bb238ab772a2000906f3958ca5f15d3a80d563f17eb4123c5b7c135b128dc0140e3d5a2a8c658ea8a47de425f1d45e429fbd84e68d9f3c7ff9cd36f1968260fa558fe15c39ac2c0096fe076b707625e1ae129e642a53081b177294251b002ddf600000000

echo "=== Test 1: Create Vault ==="
export current_block=850000
cat ./spells/create-vault.yaml | envsubst | charms spell check --prev-txs=${prev_txs} --app-bins=${app_bin}
echo "✅ Vault creation test passed!"
echo ""

echo "=== Test 2: Send Heartbeat ==="
echo "Note: This requires the actual vault UTXO from Test 1"
echo "For full testing, you would:"
echo "  1. Create vault (Test 1) and get the vault UTXO"
echo "  2. Use that UTXO here with old_heartbeat_block=850000"
echo "  3. Set current_block < old_heartbeat_block + heartbeat_interval"
echo ""

echo "=== Test 3: Release to Beneficiary ==="
echo "Note: This requires an expired vault UTXO"
echo "For full testing, you would:"
echo "  1. Have a vault with last_heartbeat_block=850000"
echo "  2. Set current_block >= last_heartbeat_block + heartbeat_interval (>= 850144)"
echo "  3. Verify funds go to beneficiary"
echo ""

echo "=== Summary ==="
echo "✅ Vault creation logic: WORKING"
echo "ℹ️  Heartbeat logic: Ready (needs actual vault UTXO)"
echo "ℹ️  Release logic: Ready (needs expired vault UTXO)"
echo ""
echo "To test heartbeat and release, you need to:"
echo "  1. Actually create a vault on testnet"
echo "  2. Get the vault UTXO from the creation transaction"
echo "  3. Use that UTXO for heartbeat/release tests"


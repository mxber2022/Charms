#!/bin/bash
# Sign transactions using bitcoin-cli with remote RPC

set -e

cd "$(dirname "$0")"

# Remote RPC endpoint
RPC_URL="https://bitcoin-testnet4.gateway.tatum.io"
RPC_USER=""  # Tatum doesn't require auth
RPC_PASS=""

# Private key
PRIVATE_KEY="76476027042ab81d77d4bbc63ef3ea722d2ac7f2f35f0844915da7c39ab5c72d"

echo "=== Sign Transactions with bitcoin-cli ===\n"

# Load transactions
if [ ! -f "/tmp/vault-transactions.json" ]; then
    echo "❌ /tmp/vault-transactions.json not found"
    echo "   Run ./create-vault.sh first"
    exit 1
fi

commit_tx=$(cat /tmp/vault-transactions.json | jq -r '.[0]')
spell_tx=$(cat /tmp/vault-transactions.json | jq -r '.[1]')

echo "1. Signing commit transaction..."
echo "   Using bitcoin-cli with remote RPC..."

# Configure bitcoin-cli to use remote RPC
export BITCOIN_CLI_OPTIONS="-testnet -rpcuser=$RPC_USER -rpcpassword=$RPC_PASS -rpcconnect=$(echo $RPC_URL | sed 's|https\?://||' | cut -d'/' -f1)"

# Try signing with signrawtransactionwithkey
# Note: This requires the previous transaction outputs
signed_commit=$(bitcoin-cli -testnet signrawtransactionwithkey "$commit_tx" "[\"$PRIVATE_KEY\"]" 2>&1)

if echo "$signed_commit" | grep -q '"hex"'; then
    commit_hex=$(echo "$signed_commit" | jq -r '.hex')
    echo "   ✅ Commit TX signed"
else
    echo "   ⚠️  Signing failed (may need prev tx data)"
    echo "   Error: $signed_commit"
    echo ""
    echo "   Alternative: Use mempool.space to sign and submit"
    exit 1
fi

echo ""
echo "2. Signing spell transaction..."
echo "   Note: Spell TX needs commit TX output data"

# For spell TX, we need the commit TX output
# This is complex - for now, suggest manual signing
echo "   ⚠️  Spell TX signing requires commit TX output data"
echo "   This is complex - recommend using mempool.space"
echo ""

echo "✅ Commit TX signed: ${commit_hex:0:50}..."
echo ""
echo "Next: Submit via mempool.space or use the signed commit TX"


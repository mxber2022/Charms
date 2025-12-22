#!/bin/bash
# Setup script for Alchemy Bitcoin Testnet RPC

export BITCOIN_TESTNET_RPC="https://bitcoin-testnet4.gateway.tatum.io"

echo "=== Bitcoin Testnet RPC Setup ==="
echo ""
echo "RPC Endpoint: $BITCOIN_TESTNET_RPC"
echo ""

# Test the RPC connection
echo "Testing RPC connection..."
response=$(curl -s -X POST "$BITCOIN_TESTNET_RPC" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"1.0","id":"test","method":"getblockchaininfo","params":[]}')

if echo "$response" | grep -q "chain"; then
    echo "✅ RPC connection successful!"
    echo "$response" | jq -r '.result | "Chain: \(.chain), Blocks: \(.blocks)"' 2>/dev/null || echo "$response"
else
    echo "⚠️  Could not verify connection. Response:"
    echo "$response"
fi

echo ""
echo "To use this RPC in your scripts, add:"
echo "export BITCOIN_TESTNET_RPC=\"$BITCOIN_TESTNET_RPC\""
echo ""
echo "Or add to your ~/.bashrc or ~/.zshrc:"
echo "export BITCOIN_TESTNET_RPC=\"$BITCOIN_TESTNET_RPC\""


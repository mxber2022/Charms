#!/bin/bash
# Helper functions for Bitcoin RPC calls using Alchemy endpoint

BITCOIN_TESTNET_RPC="${BITCOIN_TESTNET_RPC:-https://bitcoin-testnet4.gateway.tatum.io}"

# Make RPC call
bitcoin_rpc() {
    local method=$1
    shift
    local params="$@"
    
    if [ -z "$params" ]; then
        params="[]"
    else
        params="[$params]"
    fi
    
    curl -s -X POST "$BITCOIN_TESTNET_RPC" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"1.0\",\"id\":\"test\",\"method\":\"$method\",\"params\":$params}" \
        | jq -r '.result'
}

# Get block count
get_block_count() {
    bitcoin_rpc "getblockcount"
}

# Get new address
get_new_address() {
    bitcoin_rpc "getnewaddress" "" "bech32"
}

# List unspent
list_unspent() {
    bitcoin_rpc "listunspent" "0" "9999999" "[]"
}

# Get raw transaction
get_raw_transaction() {
    local txid=$1
    bitcoin_rpc "getrawtransaction" "\"$txid\""
}

# Get transaction details
get_transaction() {
    local txid=$1
    bitcoin_rpc "gettransaction" "\"$txid\""
}

# Send raw transaction
send_raw_transaction() {
    local hex=$1
    bitcoin_rpc "sendrawtransaction" "\"$hex\""
}

# Get block hash
get_block_hash() {
    local height=$1
    bitcoin_rpc "getblockhash" "$height"
}

# Export functions for use in other scripts
export -f bitcoin_rpc get_block_count get_new_address list_unspent
export -f get_raw_transaction get_transaction send_raw_transaction get_block_hash


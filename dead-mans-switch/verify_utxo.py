#!/usr/bin/env python3
"""
Verify that the funding UTXO belongs to the address
"""

import json
import urllib.request

ADDRESS = "tb1pzwhfatdwel88smwamph5z6wsskets9x2th3l2jxu27waz4jgzy7s7uh4fx"

def get_utxos(address):
    """Get UTXOs for an address"""
    url = f"https://mempool.space/testnet4/api/address/{address}/utxo"
    with urllib.request.urlopen(url) as response:
        return json.loads(response.read())

def get_transaction(txid):
    """Get transaction details"""
    url = f"https://mempool.space/testnet4/api/tx/{txid}"
    with urllib.request.urlopen(url) as response:
        return json.loads(response.read())

def main():
    print("=== Verifying Funding UTXO ===\n")
    
    # Get all UTXOs
    print(f"1. Getting UTXOs for {ADDRESS}...")
    utxos = get_utxos(ADDRESS)
    print(f"   Found {len(utxos)} UTXO(s)\n")
    
    # Show all UTXOs
    print("Available UTXOs:")
    for i, utxo in enumerate(utxos):
        print(f"  {i+1}. {utxo['txid']}:{utxo['vout']} - {utxo['value']} sats")
        if utxo.get('status', {}).get('confirmed'):
            print("     ✅ Confirmed")
        else:
            print("     ⚠️  Unconfirmed")
    
    print("\n2. Checking which UTXO was used in commit transaction...")
    
    # Load commit transaction
    try:
        with open('/tmp/vault-transactions.json', 'r') as f:
            transactions = json.load(f)
        commit_tx_hex = transactions[0]
        
        # The funding UTXO should be in the first input
        # Parse to get the input (simplified - just show the hex)
        print(f"   Commit TX hex: {commit_tx_hex[:100]}...")
        print("\n   To verify:")
        print("   - Check if the funding UTXO is in your UTXO list above")
        print("   - Verify the UTXO belongs to your address")
        print("   - Make sure it's confirmed")
        
    except FileNotFoundError:
        print("   ❌ /tmp/vault-transactions.json not found")
        print("   Run ./create-vault.sh first")

if __name__ == "__main__":
    main()


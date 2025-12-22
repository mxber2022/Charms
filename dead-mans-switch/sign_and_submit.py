#!/usr/bin/env python3
"""
Sign and submit Charms vault transactions

The transactions from charms spell prove may already be signed or need signing.
This script attempts to submit them and provides instructions if signing is needed.
"""

import json
import urllib.request

# RPC endpoint
RPC_URL = "https://bitcoin-testnet4.gateway.tatum.io"

def load_transactions():
    """Load transactions from JSON file"""
    try:
        with open('/tmp/vault-transactions.json', 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print("❌ Error: /tmp/vault-transactions.json not found")
        print("   Run ./create-vault.sh first")
        return None

def submit_transaction(tx_hex, rpc_url):
    """Submit transaction via RPC"""
    try:
        payload = {
            "method": "sendrawtransaction",
            "params": [tx_hex],
            "jsonrpc": "1.0",
            "id": "test"
        }
        
        data = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(rpc_url, data=data, headers={'Content-Type': 'application/json'})
        
        with urllib.request.urlopen(req) as response:
            result = json.loads(response.read())
            if 'result' in result:
                return result['result'], None
            elif 'error' in result:
                return None, result['error']
            return None, "Unknown error"
            
    except Exception as e:
        return None, str(e)

def submit_package(tx_hexes, rpc_url):
    """Submit transactions as a package"""
    try:
        payload = {
            "method": "submitpackage",
            "params": tx_hexes,
            "jsonrpc": "1.0",
            "id": "test"
        }
        
        data = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(rpc_url, data=data, headers={'Content-Type': 'application/json'})
        
        with urllib.request.urlopen(req) as response:
            result = json.loads(response.read())
            if 'result' in result:
                return result['result'], None
            elif 'error' in result:
                return None, result['error']
            return None, "Unknown error"
            
    except Exception as e:
        return None, str(e)

def main():
    print("=== Submit Vault Transactions ===\n")
    
    # Load transactions
    print("1. Loading transactions...")
    transactions = load_transactions()
    if not transactions:
        return
    
    commit_tx_hex = transactions[0]
    spell_tx_hex = transactions[1]
    print(f"   ✅ Commit TX: {commit_tx_hex[:50]}...")
    print(f"   ✅ Spell TX: {spell_tx_hex[:50]}...\n")
    
    # Try to submit as package first
    print("2. Attempting to submit as package...")
    result, error = submit_package([commit_tx_hex, spell_tx_hex], RPC_URL)
    
    if result:
        print("   ✅ Package submitted successfully!")
        print(f"   Result: {result}\n")
        print("✅ Transactions submitted!")
        print("\nNext steps:")
        print("1. Wait for confirmations")
        print("2. Get vault UTXO from confirmed transaction")
        print("3. Update /tmp/vault-info.json")
        print("4. Test heartbeat: ./test-heartbeat.sh")
        return
    
    if error:
        error_msg = error.get('message', str(error)) if isinstance(error, dict) else str(error)
        print(f"   ⚠️  Package submission failed: {error_msg}")
        print("   Trying individual submission...\n")
    
    # Try individual submission
    print("3. Submitting commit transaction...")
    result, error = submit_transaction(commit_tx_hex, RPC_URL)
    
    if result:
        print(f"   ✅ Commit TX submitted: {result}\n")
        
        print("4. Submitting spell transaction...")
        result, error = submit_transaction(spell_tx_hex, RPC_URL)
        
        if result:
            print(f"   ✅ Spell TX submitted: {result}\n")
            print("✅ Both transactions submitted!")
            print("\nNext steps:")
            print("1. Wait for confirmations")
            print("2. Get vault UTXO from confirmed transaction")
            print("3. Update /tmp/vault-info.json")
            print("4. Test heartbeat: ./test-heartbeat.sh")
        else:
            error_msg = error.get('message', str(error)) if isinstance(error, dict) else str(error)
            print(f"   ❌ Spell TX failed: {error_msg}")
            print("   You may need to wait for commit TX confirmation first")
    else:
        error_msg = error.get('message', str(error)) if isinstance(error, dict) else str(error)
        print(f"   ❌ Commit TX failed: {error_msg}")
        print("\n   📋 Transactions need signing. Use mempool.space:")
        print("   1. Go to: https://mempool.space/testnet4/tx/push")
        print("   2. In 'Submit Package', paste the comma-separated transactions")
        print("   3. Click Submit")
        print("\n   Package string saved to: /tmp/package_submission.txt")
        
        # Save package string
        package_str = f"{commit_tx_hex},{spell_tx_hex}"
        with open('/tmp/package_submission.txt', 'w') as f:
            f.write(package_str)
        print(f"   Length: {len(package_str)} characters")

if __name__ == "__main__":
    main()

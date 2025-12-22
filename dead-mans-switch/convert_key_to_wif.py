#!/usr/bin/env python3
"""
Convert hex private key to WIF format for bitcoin-cli
"""

import hashlib
import base58

# Private key in hex
PRIVATE_KEY_HEX = "76476027042ab81d77d4bbc63ef3ea722d2ac7f2f35f0844915da7c39ab5c72d"

def hex_to_wif(hex_key, compressed=True, testnet=True):
    """Convert hex private key to WIF format"""
    # Add version byte (0x80 for mainnet, 0xef for testnet)
    version = b'\xef' if testnet else b'\x80'
    
    # Convert hex to bytes
    key_bytes = bytes.fromhex(hex_key)
    
    # Add compression flag if needed
    if compressed:
        key_bytes += b'\x01'
    
    # Prepend version byte
    extended_key = version + key_bytes
    
    # Double SHA256
    first_hash = hashlib.sha256(extended_key).digest()
    second_hash = hashlib.sha256(first_hash).digest()
    
    # Take first 4 bytes as checksum
    checksum = second_hash[:4]
    
    # Append checksum
    final_key = extended_key + checksum
    
    # Encode to base58
    wif = base58.b58encode(final_key).decode('ascii')
    
    return wif

if __name__ == "__main__":
    print("=== Converting Private Key to WIF ===\n")
    
    try:
        wif = hex_to_wif(PRIVATE_KEY_HEX, compressed=True, testnet=True)
        print(f"Hex key: {PRIVATE_KEY_HEX}")
        print(f"WIF key: {wif}\n")
        print("Use this WIF key with bitcoin-cli signrawtransactionwithkey")
    except Exception as e:
        print(f"Error: {e}")
        print("\nNote: You may need to install base58:")
        print("  pip install base58")


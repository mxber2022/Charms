#!/usr/bin/env node
/**
 * Extract vault state from transaction using extractAndVerifySpell
 */

const assert = require('assert');
const path = require('path');
const fs = require('fs');

// Load WASM module
const wasmModulePath = path.resolve(__dirname, '../charms/charms-lib/target/wasm-bindgen-nodejs/charms_lib.js');
assert.ok(fs.existsSync(wasmModulePath), `Wasm JS glue not found at ${wasmModulePath}`);

const wasm = require(wasmModulePath);
assert.ok(typeof wasm.extractAndVerifySpell === 'function', 'extractAndVerifySpell export not found');

function extractVaultState(txHex) {
    const tx = { bitcoin: txHex };
    
    try {
        // Extract and verify spell from transaction
        const res = wasm.extractAndVerifySpell(tx, false);
        
        console.log('=== Extracted Spell Data ===');
        console.log('Version:', res.version);
        console.log('Transaction inputs:', res.tx.ins);
        console.log('Transaction outputs:', res.tx.outs);
        
        // The charm data should be in the outputs
        if (res.tx && res.tx.outs) {
            console.log('\n=== Charm Data in Outputs ===');
            res.tx.outs.forEach((output, index) => {
                console.log(`Output ${index}:`, output);
            });
        }
        
        return res;
    } catch (err) {
        console.error('Error extracting spell:', err);
        throw err;
    }
}

// Main execution
if (require.main === module) {
    const args = process.argv.slice(2);
    
    if (args.length === 0) {
        console.error('Usage: node extract-vault-state.js <tx_hex>');
        console.error('   or: node extract-vault-state.js --from-vault <vault_dir>');
        process.exit(1);
    }
    
    let txHex;
    
    if (args[0] === '--from-vault') {
        // Load from vault directory
        const vaultDir = args[1] || '../vault-data/vault-03d74c002248ef63';
        const vaultInfoPath = path.resolve(__dirname, vaultDir, 'info.json');
        
        if (!fs.existsSync(vaultInfoPath)) {
            console.error(`Vault info not found at: ${vaultInfoPath}`);
            process.exit(1);
        }
        
        const vaultInfo = JSON.parse(fs.readFileSync(vaultInfoPath, 'utf8'));
        const spellTxid = vaultInfo.spell_txid;
        
        console.log(`Loading transaction: ${spellTxid}`);
        
        // Get transaction hex using bitcoin-cli
        const { execSync } = require('child_process');
        txHex = execSync(`bitcoin-cli getrawtransaction "${spellTxid}" false`, { encoding: 'utf8' }).trim();
    } else {
        txHex = args[0];
    }
    
    extractVaultState(txHex);
}

module.exports = { extractVaultState };


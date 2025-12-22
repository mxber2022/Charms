#!/usr/bin/env node
/**
 * Test heartbeat using extractAndVerifySpell to read vault state
 */

const assert = require('assert');
const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

// Load WASM module
const wasmModulePath = path.resolve(__dirname, '../charms/charms-lib/target/wasm-bindgen-nodejs/charms_lib.js');
const wasm = require(wasmModulePath);

function extractVaultState(txHex) {
    const tx = { bitcoin: txHex };
    const res = wasm.extractAndVerifySpell(tx, false);
    
    // Extract vault state from outputs
    if (res.tx && res.tx.outs && res.tx.outs.length > 0) {
        const output = res.tx.outs[0];
        if (output instanceof Map && output.has(0)) {
            const charmData = output.get(0);
            if (charmData instanceof Map) {
                const state = {};
                for (const [key, value] of charmData.entries()) {
                    state[key] = value;
                }
                return state;
            }
        }
    }
    return null;
}

function main() {
    console.log('=== Testing Heartbeat with extractAndVerifySpell ===\n');
    
    // Load vault info
    const vaultDir = path.resolve(__dirname, '../vault-data/vault-03d74c002248ef63');
    const vaultInfoPath = path.join(vaultDir, 'info.json');
    
    if (!fs.existsSync(vaultInfoPath)) {
        console.error(`Vault info not found at: ${vaultInfoPath}`);
        process.exit(1);
    }
    
    const vaultInfo = JSON.parse(fs.readFileSync(vaultInfoPath, 'utf8'));
    const spellTxid = vaultInfo.spell_txid;
    const vaultUtxo = vaultInfo.vault_utxo;
    
    console.log('Vault Info:');
    console.log(`  Spell TXID: ${spellTxid}`);
    console.log(`  Vault UTXO: ${vaultUtxo}`);
    console.log(`  App ID: ${vaultInfo.app_id}`);
    console.log('');
    
    // Get current block
    console.log('1. Getting current block...');
    const currentBlock = parseInt(execSync('bitcoin-cli getblockcount', { encoding: 'utf8' }).trim());
    console.log(`   ✅ Current block: ${currentBlock}`);
    
    // Get transaction that created the vault
    console.log('\n2. Reading vault state from transaction...');
    const txHex = execSync(`bitcoin-cli getrawtransaction "${spellTxid}" false`, { encoding: 'utf8' }).trim();
    console.log(`   ✅ Got transaction (${txHex.length} chars)`);
    
    // Extract vault state
    const vaultState = extractVaultState(txHex);
    
    if (!vaultState) {
        console.error('   ❌ Could not extract vault state from transaction');
        process.exit(1);
    }
    
    console.log('   ✅ Extracted vault state:');
    console.log(`      owner: ${vaultState.owner}`);
    console.log(`      beneficiary: ${vaultState.beneficiary}`);
    console.log(`      last_heartbeat_block: ${vaultState.last_heartbeat_block}`);
    console.log(`      heartbeat_interval: ${vaultState.heartbeat_interval}`);
    
    // Validate heartbeat
    console.log('\n3. Validating heartbeat...');
    const blocksSinceHeartbeat = currentBlock - vaultState.last_heartbeat_block;
    const heartbeatInterval = vaultState.heartbeat_interval;
    
    console.log(`   Blocks since heartbeat: ${blocksSinceHeartbeat}`);
    console.log(`   Heartbeat interval: ${heartbeatInterval}`);
    
    if (blocksSinceHeartbeat >= heartbeatInterval) {
        console.log('   ❌ Heartbeat has EXPIRED!');
        console.log(`      ${blocksSinceHeartbeat} >= ${heartbeatInterval}`);
        console.log('   Cannot send heartbeat. Use release instead.');
        process.exit(1);
    }
    
    console.log(`   ✅ Heartbeat is VALID (${blocksSinceHeartbeat} < ${heartbeatInterval})`);
    
    // Check if we can create heartbeat transaction
    console.log('\n4. Ready to create heartbeat transaction');
    console.log('   The heartbeat will update:');
    console.log(`      last_heartbeat_block: ${vaultState.last_heartbeat_block} → ${currentBlock}`);
    console.log('');
    console.log('   Next steps:');
    console.log('   1. Run: ./test-heartbeat.sh');
    console.log('   2. Or use charms spell prove to create transaction');
    console.log('   3. Sign with bitcoin-cli or Scrolls API');
    console.log('   4. Submit to network');
}

if (require.main === module) {
    try {
        main();
    } catch (err) {
        console.error('Error:', err.message);
        process.exit(1);
    }
}

module.exports = { extractVaultState };


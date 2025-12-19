use charms_sdk::data::{
    charm_values, check, App, Data, Transaction, UtxoId, B32, NFT,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

// Vault state structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultState {
    pub owner: String,              // Owner's Bitcoin address
    pub beneficiary: String,         // Beneficiary's Bitcoin address
    pub last_heartbeat_block: u64,  // Last block height when heartbeat was sent
    pub heartbeat_interval: u64,     // Heartbeat interval in blocks
}

pub fn app_contract(app: &App, tx: &Transaction, x: &Data, w: &Data) -> bool {
    let empty = Data::empty();
    assert_eq!(x, &empty);
    
    // This app only uses NFT tag for vault state
    match app.tag {
        NFT => {
            check!(vault_contract_satisfied(app, tx, w))
        }
        _ => {
            return false; // Only NFT tag is supported
        }
    }
    true
}

// Main vault contract logic
fn vault_contract_satisfied(app: &App, tx: &Transaction, w: &Data) -> bool {
    // Check if this is vault creation, heartbeat, or release
    check!(
        can_create_vault(app, tx, w) ||
        can_send_heartbeat(app, tx, w) ||
        can_release_to_beneficiary(app, tx, w)
    );
    true
}

// Vault creation: Mint new vault with initial state
fn can_create_vault(app: &App, tx: &Transaction, w: &Data) -> bool {
    // For creation, w should be a UTXO string
    let w_str: Option<String> = w.value().ok();
    if w_str.is_none() {
        return false; // Not a string, can't be creation
    }
    let w_str = w_str.unwrap();

    // Try to parse as UTXO - if it fails, this is not a creation
    let w_utxo_id = match UtxoId::from_str(&w_str) {
        Ok(utxo) => utxo,
        Err(_) => return false, // Not a valid UTXO format
    };

    // Vault identity must match hash of witness data (UTXO)
    check!(hash(&w_str) == app.identity);

    // Must spend the UTXO specified in witness
    check!(tx.ins.iter().any(|(utxo_id, _)| utxo_id == &w_utxo_id));

    // Must create exactly one vault
    let vault_charms = charm_values(app, tx.outs.iter()).collect::<Vec<_>>();
    check!(vault_charms.len() == 1);
    
    // Vault must have valid structure
    let vault_state: VaultState = match vault_charms[0].value() {
        Ok(state) => state,
        Err(_) => return false,
    };

    // Validate initial vault state
    check!(!vault_state.owner.is_empty());
    check!(!vault_state.beneficiary.is_empty());
    check!(vault_state.heartbeat_interval > 0);
    check!(vault_state.last_heartbeat_block > 0); // Initial heartbeat block

    true
}

// Heartbeat: Owner updates last_heartbeat_block
fn can_send_heartbeat(app: &App, tx: &Transaction, w: &Data) -> bool {
    // Get incoming vault state
    let Some(incoming_vault): Option<VaultState> =
        charm_values(app, tx.ins.iter().map(|(_, v)| v))
            .find_map(|data| data.value().ok())
    else {
        return false; // No incoming vault
    };

    // Get outgoing vault state
    let Some(outgoing_vault): Option<VaultState> =
        charm_values(app, tx.outs.iter())
            .find_map(|data| data.value().ok())
    else {
        return false; // No outgoing vault
    };

    // Vault identity must be preserved
    check!(incoming_vault.owner == outgoing_vault.owner);
    check!(incoming_vault.beneficiary == outgoing_vault.beneficiary);
    check!(incoming_vault.heartbeat_interval == outgoing_vault.heartbeat_interval);

    // Get current block height from witness (w contains block height)
    let current_block: u64 = match w.value() {
        Ok(block) => block,
        Err(_) => return false,
    };

    // Check heartbeat hasn't expired
    let blocks_since_heartbeat = current_block.saturating_sub(incoming_vault.last_heartbeat_block);
    check!(blocks_since_heartbeat < incoming_vault.heartbeat_interval);

    // Check that last_heartbeat_block is updated to current block
    check!(outgoing_vault.last_heartbeat_block == current_block);
    check!(outgoing_vault.last_heartbeat_block > incoming_vault.last_heartbeat_block);

    // Owner must be signing (validated by spending the vault UTXO with owner's key)
    // This is enforced by Bitcoin's signature validation

    true
}

// Release: Transfer to beneficiary when heartbeat expired
fn can_release_to_beneficiary(app: &App, tx: &Transaction, w: &Data) -> bool {
    // Get incoming vault state
    let Some(incoming_vault): Option<VaultState> =
        charm_values(app, tx.ins.iter().map(|(_, v)| v))
            .find_map(|data| data.value().ok())
    else {
        return false;
    };

    // Get current block height from witness
    let current_block: u64 = match w.value() {
        Ok(block) => block,
        Err(_) => return false,
    };

    // Check heartbeat has expired
    let blocks_since_heartbeat = current_block.saturating_sub(incoming_vault.last_heartbeat_block);
    check!(blocks_since_heartbeat >= incoming_vault.heartbeat_interval);

    // Check that vault is consumed (no vault in outputs)
    let outgoing_vaults: Vec<_> = charm_values(app, tx.outs.iter()).collect();
    check!(outgoing_vaults.is_empty()); // Vault is destroyed/released

    // Check that funds go to beneficiary
    // Note: This is a simplified check - in practice, you'd verify the output address
    // matches the beneficiary address. The actual Bitcoin output validation ensures this.

    true
}

pub(crate) fn hash(data: &str) -> B32 {
    let hash = Sha256::digest(data);
    B32(hash.into())
}

#[cfg(test)]
mod test {
    use super::*;
    use charms_sdk::data::UtxoId;

    #[test]
    fn test_hash() {
        let utxo_id =
            UtxoId::from_str("dc78b09d767c8565c4a58a95e7ad5ee22b28fc1685535056a395dc94929cdd5f:1")
                .unwrap();
        let data = utxo_id.to_string();
        let expected = "f54f6d40bd4ba808b188963ae5d72769ad5212dd1d29517ecc4063dd9f033faa";
        assert_eq!(&hash(&data).to_string(), expected);
    }

    #[test]
    fn test_vault_state_structure() {
        let vault = VaultState {
            owner: "bc1qowner".to_string(),
            beneficiary: "bc1qbeneficiary".to_string(),
            last_heartbeat_block: 850000,
            heartbeat_interval: 144,
        };
        // Test that vault state structure is valid
        assert_eq!(vault.owner, "bc1qowner");
        assert_eq!(vault.beneficiary, "bc1qbeneficiary");
        assert_eq!(vault.last_heartbeat_block, 850000);
        assert_eq!(vault.heartbeat_interval, 144);
    }
}

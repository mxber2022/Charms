# Bitcoin Inheritance Vault (Dead Man’s Switch)

**Programmable Bitcoin UTXOs powered by Charms**

## Overview

**Bitcoin Inheritance Vault** is a trustless, non-custodial dead man’s switch for Bitcoin.

It allows a Bitcoin holder to lock BTC into a **programmable UTXO** that requires periodic **heartbeats** (proof of liveness).
If the owner stops sending heartbeats, the funds are **automatically released to a beneficiary** — without multisig, lawyers, or custodians.

This is made possible by **Charms**, which adds programmable logic directly to Bitcoin UTXOs.

---

## Problem

Bitcoin has no native way to handle inheritance:

* ❌ No conditional ownership transfer
* ❌ No time-based logic inside UTXOs
* ❌ Multisig setups are complex and risky
* ❌ Custodial solutions break Bitcoin’s trust model

If keys are lost or the owner dies, funds are often **lost forever**.

---

## Solution

We use **Charms Protocol** to embed programmable logic directly into a Bitcoin UTXO:

* The owner must periodically prove they are alive (**heartbeat**)
* If the heartbeat expires:

  * Ownership automatically transfers
  * Funds can only be spent to a predefined beneficiary

All rules are enforced **on Bitcoin**, not off-chain.

---

## Core Concept: Heartbeat

A **heartbeat** is an owner-signed Bitcoin transaction that updates the vault’s state.

* It proves the owner still controls the private key
* It resets the inheritance timer
* It is fully on-chain and trustless

If no heartbeat is sent before the deadline, inheritance is triggered.

---

## How It Works (High Level)

1. **Vault Creation**

   * Owner locks BTC into a Charm-enabled UTXO
   * Sets:

     * Beneficiary address
     * Heartbeat interval (in blocks)

2. **Heartbeat**

   * Owner sends a signed transaction
   * Vault state updates with latest block height

3. **Inheritance Trigger**

   * If heartbeat expires:

     * Anyone can trigger release
     * Funds can only go to beneficiary

---

## Charm Logic (Simplified)

```text
IF action == heartbeat
  AND signer == owner
  AND heartbeat not expired
→ update lastHeartbeatBlock

IF action == release
  AND heartbeat expired
→ send BTC to beneficiary
```

This logic is enforced by Bitcoin validation rules.

---

## Why Charms?

Without Charms, Bitcoin UTXOs:

* Cannot store state
* Cannot enforce time-based logic
* Cannot restrict spend destinations conditionally

**Charms enables programmable Bitcoin** by allowing:

* Stateful UTXOs
* Custom spend rules
* Block-height-based conditions

---

## Tech Stack

* **Charms Protocol SDK**
* **TypeScript**

---

## Security Properties

* Only the owner can send heartbeats
* Beneficiary cannot access funds early
* Owner cannot block inheritance after timeout
* No backend trust required
* No custodial risk

---

## Limitations (Current)

* Single beneficiary
* Manual heartbeat (no reminders)
* Testnet only

---

## Future Improvements

* Multiple beneficiaries
* Gradual release (vesting)
* Social recovery guardians
* Off-chain reminder service
* Legal document hash anchoring
* Mainnet deployment

---

## Why This Matters

Lost Bitcoin due to death or lost keys is estimated in the **millions of BTC**.
This project demonstrates how **programmable UTXOs** can solve a real, emotional, and financially critical problem — **without breaking Bitcoin’s trust model**.

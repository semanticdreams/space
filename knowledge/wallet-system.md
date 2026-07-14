---
type: feature
status: shipped
parent-goal: "[[core-platform]]"
tags:
  - feature
  - wallet
  - crypto
  - blockchain
created: 2026-07-14
updated: 2026-07-14
---

# Wallet system

## Summary

Crypto wallet with mnemonic generation, Arbitrum Nova transfers, transaction signing, and encrypted persistence. Built on wallet-core C++ bindings with Fennel modules for wallet lifecycle, RPC interaction, and UI dialogs.

## Motivation

Space needed a built-in wallet for future social/contribution features (one-click tipping, asset distribution) and as a foundation for user-owned services. The wallet-core library provides cross-chain cryptographic operations; the Fennel layer wraps it with application-level wallet management.

## Design

- **Wallet** (`wallet.fnl`): Core operations — mnemonic generation/validation, Arbitrum Nova account creation, transfer signing (ETH/ERC-20). Exposes `validate-mnemonic`, `generate-mnemonic`, `create-arbitrumnova`, `sign-arbitrumnova-transfer`.
- **WalletStore** (`wallet-store.fnl`): Encrypted JSON persistence for wallet mnemonics and addresses.
- **WalletManager** (`wallet-manager.fnl`): Lifecycle management — load, create, recover, switch active wallet.
- **WalletRPC** (`wallet-rpc.fnl`): RPC client for chain interaction (balance queries, transaction submission) on Arbitrum Nova chain ID 42170.
- **WalletTxUtils** (`wallet-tx-utils.fnl`): Transaction utilities — ETH/wei conversion, hex/base64 encoding.
- **Dialogs**: `wallet-create-dialog.fnl`, `wallet-load-dialog.fnl`, `wallet-recover-dialog.fnl`, `wallet-send-dialog.fnl` — full UI for wallet operations.
- **WalletView** (`wallet-view.fnl`): Wallet balance and transaction view widget.

## Tasks

- [x] wallet-core C++ binding
- [x] Mnemonic generation (128-bit strength)
- [x] Arbitrum Nova account creation
- [x] Transaction signing
- [x] Encrypted wallet persistence
- [x] RPC client for chain interaction
- [x] Create/load/recover/send dialogs
- [x] Wallet view widget

## Related

- Goal: [[core-platform]]
- See: [[subsystems]] — Wallet engine section
- See: [[milestones]] (Milestone 11 — User-owned services)
- See: [[dev-notes/wallet]], [[dev-notes/wallet-core]]

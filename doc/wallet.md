# Wallet Features

## Implemented

- Wallet-core integration with Fennel bindings (`wallet-core`, `HDWallet`, JSON signing).
- Arbitrum Nova wallet creation:
  - Generate or supply mnemonic.
  - Derive address from BIP-44 path `m/44'/60'/0'/0/0`.
- Wallet persistence:
  - Metadata stored under `appdirs.user-data-dir` (`wallets/metadata.json`).
  - Mnemonic stored in keyring by wallet id.
  - Active wallet tracked in `wallets/active.json`.
- Wallet view (HUD):
  - Show active wallet name, coin, address, and balance.
  - Copy address to clipboard.
  - Receive QR code for the address.
  - Balance refresh with explicit reload button.
- Wallet dialogs:
  - Create wallet dialog (name + mnemonic).
  - Load wallet dialog (list of saved wallets).
  - Send dialog (Arbitrum Nova only):
    - Recipient, amount (ETH), optional data hex.
    - Auto-fetch nonce, gas price, and gas limit.
    - Sign via `HDWallet:sign-json` and send via RPC.
    - Shows status + transaction hash.
- RPC integration (Arbitrum Nova):
  - `eth_getBalance`, `eth_getTransactionCount`, `eth_gasPrice`, `eth_estimateGas`,
    `eth_sendRawTransaction`.
  - Default endpoint: `https://nova.arbitrum.io/rpc`.

## Current Limitations

- Send flow uses legacy gas price only (no EIP-1559 fields).
- Only Arbitrum Nova is exposed in app UX (wallet-core bindings also expose Arbitrum One and Ethereum
  address derivation, but UI and RPC are Nova-focused).
- No transaction history, receipts, or pending tracking.
- No token support (ERC-20/721/1155), no fiat conversions.
- No address book or contact tagging.

## Roadmap Ideas

### EIP-1559 Support (planned)

Add inputs and signer wiring for EIP-1559 transactions:

- UI inputs in Send dialog:
  - `max_fee_per_gas` (max fee)
  - `max_priority_fee_per_gas` (max priority fee)
  - Optional toggle to use legacy gas price vs EIP-1559 fields.
- RPC additions:
  - `eth_feeHistory` to propose base fee / priority fee defaults.
  - `eth_maxPriorityFeePerGas` as an optional shortcut.
- Signer wiring:
  - Extend the JSON payload used by `TWAnySignerSignJSON` to include
    `maxFeePerGas` and `maxInclusionFeePerGas` (priority fee) for the Ethereum
    signer.
  - Set transaction mode to EIP-1559 (wallet-core Ethereum proto supports this via
    `TransactionMode::Enveloped`).
  - Ensure the signer path remains Arbitrum Nova-compatible (same EVM signing rules).

### Additional Features

- Chain selector (Arbitrum One, Arbitrum Nova, Ethereum mainnet/testnets).
- Address book and saved recipients.
- Transaction history + receipts with status updates.
- Token balances and transfers (ERC-20, ERC-721, ERC-1155).
- Multiple accounts per mnemonic (indexing beyond `m/44'/60'/0'/0/0`).
- QR encoding of payment requests (amount, memo) and configurable URI schemes.
- Hardware wallet support (Ledger, Trezor) via wallet-core if supported.
- Optional encrypted file storage for mnemonics (in addition to keyring).

(local wallet-core (require :wallet-core))
(local json (require :json))
(local WalletTxUtils (require :wallet-tx-utils))

(local Wallet {})
(local ARBITRUM_NOVA_CHAIN_ID "42170")

(fn Wallet.validate-mnemonic [mnemonic]
  (wallet-core.mnemonic-valid mnemonic))

(fn Wallet.generate-mnemonic [opts]
  (local options (or opts {}))
  (wallet-core.generate-mnemonic
    {:strength (or options.strength 128)
     :passphrase (or options.passphrase "")}))

(fn Wallet.create-arbitrumnova [opts]
  (local options (or opts {}))
  (local provided (or options.mnemonic ""))
  (local passphrase (or options.passphrase ""))
  (local mnemonic
    (if (= provided "")
        (Wallet.generate-mnemonic {:strength (or options.strength 128)
                                   :passphrase passphrase})
        provided))
  (assert (not= mnemonic "") "Wallet.create-arbitrumnova requires mnemonic")
  (local wallet (wallet-core.HDWallet {:mnemonic mnemonic :passphrase passphrase}))
  (local coin-types (. wallet-core :coin-types))
  (local address (wallet:address-for-coin (. coin-types :arbitrumnova)))
  (wallet:drop)
  {:mnemonic mnemonic
   :address address})

(fn Wallet.sign-arbitrumnova-transfer [opts]
  (local options (or opts {}))
  (local wallet (or options.wallet options.active-wallet))
  (assert wallet "Wallet.sign-arbitrumnova-transfer requires wallet")
  (assert wallet.mnemonic "Wallet.sign-arbitrumnova-transfer requires wallet mnemonic")
  (assert wallet.address "Wallet.sign-arbitrumnova-transfer requires wallet address")
  (local to-address (or options.to options.to-address))
  (local amount-eth (or options.amount-eth options.amount))
  (local nonce-hex (or options.nonce options.nonce-hex))
  (local gas-price-hex (or options.gas-price options.gas-price-hex))
  (local gas-limit-hex (or options.gas-limit options.gas-limit-hex))
  (local data-hex (or options.data options.data-hex))
  (assert to-address "Wallet.sign-arbitrumnova-transfer requires recipient address")
  (assert amount-eth "Wallet.sign-arbitrumnova-transfer requires amount")
  (assert nonce-hex "Wallet.sign-arbitrumnova-transfer requires nonce")
  (assert gas-price-hex "Wallet.sign-arbitrumnova-transfer requires gas price")
  (assert gas-limit-hex "Wallet.sign-arbitrumnova-transfer requires gas limit")
  (local wei (WalletTxUtils.eth-to-wei amount-eth))
  (local input {:chainId (WalletTxUtils.decimal-to-base64 ARBITRUM_NOVA_CHAIN_ID)
                :nonce (WalletTxUtils.hex-to-base64 nonce-hex)
                :gasPrice (WalletTxUtils.hex-to-base64 gas-price-hex)
                :gasLimit (WalletTxUtils.hex-to-base64 gas-limit-hex)
                :toAddress to-address
                :transaction {:transfer {:amount (WalletTxUtils.decimal-to-base64 wei)}}})
  (local transfer (. (. input :transaction) :transfer))
  (when (and data-hex (not (= data-hex "")))
    (tset transfer :data
          (WalletTxUtils.hex-to-base64 data-hex)))
  (local wallet-hd (wallet-core.HDWallet {:mnemonic wallet.mnemonic :passphrase ""}))
  (local coin-types (. wallet-core :coin-types))
  (local payload (json.dumps input))
  (local signed (wallet-hd:sign-json (. coin-types :arbitrumnova) payload))
  (wallet-hd:drop)
  signed)

Wallet

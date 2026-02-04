(local wallet-core (require :wallet-core))

(if (= (. wallet-core :available) false)
    {:name "wallet-core"
     :tests []
     :main (fn []
             (print "wallet-core unavailable; skipping tests"))}
    (do
        (local tests [])

        (local mnemonic "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")

        (fn mnemonic-validation []
            (assert (wallet-core.mnemonic-valid mnemonic) "Valid mnemonic should pass validation")
            (assert (not (wallet-core.mnemonic-valid "invalid words"))
                    "Invalid mnemonic should fail validation"))

        (fn hdwallet-rejects-invalid-mnemonic []
            (local (ok err)
                   (pcall (fn [] (wallet-core.HDWallet {:mnemonic "invalid words"}))))
            (assert (not ok) "HDWallet should reject invalid mnemonic")
            (assert err "HDWallet should return an error for invalid mnemonic"))

        (fn hdwallet-derives-bitcoin-address []
            (local wallet (wallet-core.HDWallet {:mnemonic mnemonic :passphrase ""}))
            (local coin-types (. wallet-core :coin-types))
            (local address (wallet:address-for-coin (. coin-types :bitcoin)))
            (assert (= (wallet:mnemonic) mnemonic) "Wallet mnemonic should round-trip")
            (assert (= address "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu")
                    "Wallet should derive the expected Bitcoin address")
            (wallet:drop))

        (fn hdwallet-derives-evm-addresses []
            (local wallet (wallet-core.HDWallet {:mnemonic mnemonic :passphrase ""}))
            (local coin-types (. wallet-core :coin-types))
            (local expected "0x9858EfFD232B4033E47d90003D41EC34EcaEda94")
            (assert (. coin-types :arbitrum) "Arbitrum coin type should be exposed")
            (assert (. coin-types :arbitrumnova) "Arbitrum Nova coin type should be exposed")
            (assert (= (wallet:address-for-coin (. coin-types :ethereum)) expected)
                    "Wallet should derive the expected Ethereum address")
            (assert (= (wallet:address-for-coin (. coin-types :arbitrum)) expected)
                    "Wallet should derive the expected Arbitrum address")
            (assert (= (wallet:address-for-coin (. coin-types :arbitrumnova)) expected)
                    "Wallet should derive the expected Arbitrum Nova address")
            (wallet:drop))

        (fn generate-mnemonic-returns-valid []
            (local generated (wallet-core.generate-mnemonic {}))
            (assert generated "Generated mnemonic should be non-empty")
            (assert (wallet-core.mnemonic-valid generated) "Generated mnemonic should validate"))

        (table.insert tests {:name "Mnemonic validation" :fn mnemonic-validation})
        (table.insert tests {:name "Reject invalid mnemonic" :fn hdwallet-rejects-invalid-mnemonic})
        (table.insert tests {:name "Derive Bitcoin address" :fn hdwallet-derives-bitcoin-address})
        (table.insert tests {:name "Derive EVM addresses" :fn hdwallet-derives-evm-addresses})
        (table.insert tests {:name "Generate mnemonic" :fn generate-mnemonic-returns-valid})

        (local main
            (fn []
                (local runner (require :tests/runner))
                (runner.run-tests {:name "wallet-core"
                                   :tests tests})))

        {:name "wallet-core"
         :tests tests
         :main main}))

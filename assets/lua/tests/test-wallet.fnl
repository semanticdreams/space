(local wallet-core (require :wallet-core))
(local Wallet (require :wallet))

(if (= (. wallet-core :available) false)
    {:name "wallet"
     :tests []
     :main (fn []
             (print "wallet-core unavailable; skipping tests"))}
    (do
        (local tests [])

        (local mnemonic "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        (local expected-address "0x9858EfFD232B4033E47d90003D41EC34EcaEda94")

        (fn wallet-creates-arbitrumnova []
            (local result (Wallet.create-arbitrumnova {:mnemonic mnemonic :passphrase ""}))
            (assert (= result.mnemonic mnemonic) "Wallet should keep mnemonic")
            (assert (= result.address expected-address) "Wallet should derive Arbitrum Nova address"))

        (fn wallet-rejects-invalid-mnemonic []
            (local (ok err)
                   (pcall (fn [] (Wallet.create-arbitrumnova {:mnemonic "invalid words"}))))
            (assert (not ok) "Wallet should reject invalid mnemonic")
            (assert err "Wallet should return an error for invalid mnemonic"))

        (fn wallet-generates-mnemonic []
            (local result (Wallet.create-arbitrumnova {}))
            (assert result.mnemonic "Wallet should generate mnemonic")
            (assert (Wallet.validate-mnemonic result.mnemonic)
                    "Generated mnemonic should be valid")
            (assert result.address "Wallet should return an address"))

        (table.insert tests {:name "Create Arbitrum Nova wallet" :fn wallet-creates-arbitrumnova})
        (table.insert tests {:name "Reject invalid mnemonic" :fn wallet-rejects-invalid-mnemonic})
        (table.insert tests {:name "Generate mnemonic" :fn wallet-generates-mnemonic})

        (local main
            (fn []
                (local runner (require :tests/runner))
                (runner.run-tests {:name "wallet"
                                   :tests tests})))

        {:name "wallet"
         :tests tests
         :main main}))

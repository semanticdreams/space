(local _ (require :main))
(local fixtures (require :tests/http-fixtures))
(local WalletRpc (require :wallet-rpc))

(local tests [])

(fn with-mock [fixture-name f]
    (assert app.engine.get-asset-path "app.engine.get-asset-path must be available")
    (local fixture-path (app.engine.get-asset-path fixture-name))
    (local fixture (fixtures.read-json fixture-path))
    (local install (fixtures.install-mock fixture))
    (local (ok result) (pcall f install.mock))
    (install.restore)
    (if ok
        result
        (error result)))

(fn wallet-rpc-balance-success []
    (with-mock "lua/tests/data/arbitrum-nova-balance-fixture.json"
               (fn [mock]
                   (local client (WalletRpc {:http mock.binding
                                             :base_url "https://nova.arbitrum.io/rpc"}))
                   (local future (client:fetch-balance "0xdeadbeef"))
                   (local result (client:wait future 2))
                   (assert (= result "0x2a") "wallet rpc should return balance hex")
                   (local requests (mock.requests))
                   (local req (. requests 1))
                   (assert (= req.method "POST") "wallet rpc should POST")
                   (assert (= req.url "https://nova.arbitrum.io/rpc") "wallet rpc should use base url"))))

(fn wallet-rpc-balance-rejects-error []
    (with-mock "lua/tests/data/arbitrum-nova-balance-fixture.json"
               (fn [mock]
                   (local client (WalletRpc {:http mock.binding
                                             :base_url "https://nova.arbitrum.io/rpc"}))
                   (local warmup (client:fetch-balance "0xdeadbeef"))
                   (client:wait warmup 2)
                   (local future (client:fetch-balance "0xdeadbeef"))
                   (local (ok err) (pcall (fn [] (client:wait future 2))))
                   (assert (not ok) "wallet rpc should reject rpc errors")
                   (assert (string.match (tostring err) "bad request")
                           "wallet rpc error should include message"))))

(fn wallet-rpc-balance-rejects-http []
    (with-mock "lua/tests/data/arbitrum-nova-balance-fixture.json"
               (fn [mock]
                   (local client (WalletRpc {:http mock.binding
                                             :base_url "https://nova.arbitrum.io/rpc"}))
                   (local warmup (client:fetch-balance "0xdeadbeef"))
                   (client:wait warmup 2)
                   (local warmup-error (client:fetch-balance "0xdeadbeef"))
                   (pcall (fn [] (client:wait warmup-error 2)))
                   (local future (client:fetch-balance "0xdeadbeef"))
                   (local (ok err) (pcall (fn [] (client:wait future 2))))
                   (assert (not ok) "wallet rpc should reject http errors")
                   (assert (string.match (tostring err) "HTTP request failed")
                           "wallet rpc http error should include status"))))

(fn wallet-rpc-send-flow []
    (with-mock "lua/tests/data/arbitrum-nova-send-fixture.json"
               (fn [mock]
                   (local client (WalletRpc {:http mock.binding
                                             :base_url "https://nova.arbitrum.io/rpc"}))
                   (local nonce-future (client:fetch-nonce "0xdeadbeef"))
                   (local nonce (client:wait nonce-future 2))
                   (assert (= nonce "0x1") "wallet rpc should return nonce hex")
                   (local gas-price-future (client:fetch-gas-price))
                   (local gas-price (client:wait gas-price-future 2))
                   (assert (= gas-price "0x2a") "wallet rpc should return gas price hex")
                   (local estimate-future
                       (client:estimate-gas {:from "0xdeadbeef"
                                             :to "0xabc"
                                             :value "0x1"}))
                   (local gas-limit (client:wait estimate-future 2))
                   (assert (= gas-limit "0x5208") "wallet rpc should return gas limit hex")
                   (local send-future (client:send-raw-transaction "0x1234"))
                   (local tx-hash (client:wait send-future 2))
                   (assert (= tx-hash "0xabc123") "wallet rpc should return tx hash")
                   (local requests (mock.requests))
                   (assert (= (# requests) 4) "wallet rpc should issue 4 requests"))))

(table.insert tests {:name "Wallet RPC balance success" :fn wallet-rpc-balance-success})
(table.insert tests {:name "Wallet RPC balance rejects rpc error" :fn wallet-rpc-balance-rejects-error})
(table.insert tests {:name "Wallet RPC balance rejects http error" :fn wallet-rpc-balance-rejects-http})
(table.insert tests {:name "Wallet RPC send flow" :fn wallet-rpc-send-flow})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "wallet-rpc"
                           :tests tests})))

{:name "wallet-rpc"
 :tests tests
 :main main}

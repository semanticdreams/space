(local json (require :json))
(local HttpCommon (require :http/common))
(var http nil)

(fn make-future [poll-fn]
    (var done? false)
    (var ok? false)
    (var value nil)
    (var err nil)
    (var source "pending")
    (var listeners [])
    (var cancel-fn nil)

    (fn notify []
        (each [_ cb (ipairs listeners)]
            (cb ok? value err source))
        (set listeners []))

    (fn resolve [result origin]
        (when (not done?)
            (set done? true)
            (set ok? true)
            (set value result)
            (set source origin)
            (notify)))

    (fn reject [message]
        (when (not done?)
            (set done? true)
            (set ok? false)
            (set err message)
            (notify)))

    (fn cancel []
        (when (not done?)
            (when cancel-fn
                (cancel-fn))
            (reject "cancelled")))

    (fn set-cancel [cb]
        (set cancel-fn cb))

    (fn on-complete [cb]
        (assert (= (type cb) :function) "future.on-complete expects a function")
        (if done?
            (cb ok? value err source)
            (table.insert listeners cb)))

    (fn await [timeout]
        (local deadline (and timeout (+ (os.clock) timeout)))
        (while (not done?)
            (when poll-fn
                (poll-fn))
            (when (and deadline (> (os.clock) deadline))
                (reject "timeout waiting for response")))
        (if ok?
            value
            (error err)))

    {:resolve resolve
     :reject reject
     :cancel cancel
     :set-cancel set-cancel
     :on-complete on-complete
     :await await
     :done? (fn [] done?)
     :ok? (fn [] ok?)
     :error (fn [] err)
     :source (fn [] source)
     :value (fn [] value)})

(fn WalletRpc [opts]
    (local options (or opts {}))
    (var http-binding (or options.http http))
    (when (not http-binding)
        (set http (require :http))
        (set http-binding http))
    (assert http-binding "WalletRpc requires the http binding")
    (assert json "WalletRpc requires the json module")

    (local base-url (or options.base_url "https://nova.arbitrum.io/rpc"))
    (var pending {})
    (var next-rpc-id 1)

    (fn next-id []
        (local id next-rpc-id)
        (set next-rpc-id (+ next-rpc-id 1))
        id)

    (fn pending-count [_self]
        (var count 0)
        (each [_ _entry (pairs pending)]
            (set count (+ count 1)))
        count)

    (fn reject-entry [entry message]
        (when entry
            (entry.future.reject message)))

    (fn process-response [res]
        (local entry (. pending res.id))
        (when entry
            (set (. pending res.id) nil)
            (if (and res.ok (< res.status 400))
                (do
                    (local (ok parsed-or-err)
                        (pcall (fn [] (HttpCommon.decode-json! res.body "Failed to decode JSON"))))
                    (if ok
                        (do
                            (local rpc-id (and parsed-or-err parsed-or-err.id))
                            (local rpc-error (and parsed-or-err parsed-or-err.error))
                            (local rpc-result (and parsed-or-err parsed-or-err.result))
                            (if (and rpc-id (not (= rpc-id entry.rpc-id)))
                                (reject-entry entry "Wallet RPC response id mismatch")
                                (if rpc-error
                                    (reject-entry entry (or rpc-error.message "Wallet RPC error"))
                                    (if (not (= rpc-result nil))
                                        (entry.future.resolve rpc-result "network")
                                        (reject-entry entry "Wallet RPC missing result")))))
                        (reject-entry entry parsed-or-err)))
                (reject-entry entry (or res.error (.. "HTTP request failed with status " res.status))))))

    (fn poll [_self max-results]
        (each [_ res (ipairs (http-binding.poll max-results))]
            (process-response res)))

    (fn wait [_self future timeout]
        (HttpCommon.poll-until poll (fn [] (future.done?)) timeout "timeout waiting for wallet rpc response")
        (if (future.ok?)
            (future.value)
            (error (future.error))))

    (fn drop [_self]
        (each [id entry (pairs pending)]
            (when http-binding.cancel
                (http-binding.cancel id))
            (entry.future.reject "client dropped"))
        (set pending {}))

    (fn submit [method params]
        (local rpc-id (next-id))
        (local payload {:jsonrpc "2.0"
                        :id rpc-id
                        :method method
                        :params params})
        (local id (http-binding.request {:method "POST"
                                         :url base-url
                                         :headers {"Content-Type" "application/json"}
                                         :body (json.dumps payload)
                                         :timeout-ms 10000
                                         :connect-timeout-ms 5000}))
        (local future (make-future poll))
        (future.set-cancel
         (fn []
             (when http-binding.cancel
                 (http-binding.cancel id))
             (set (. pending id) nil)
             (future.reject "cancelled")))
        (set (. pending id) {:future future :rpc-id rpc-id})
        future)

    (fn fetch-balance [_self address]
        (assert address "WalletRpc.fetch-balance requires an address")
        (assert (= (type address) :string) "WalletRpc.fetch-balance requires address string")
        (submit "eth_getBalance" [address "latest"]))

    (fn fetch-nonce [_self address]
        (assert address "WalletRpc.fetch-nonce requires an address")
        (assert (= (type address) :string) "WalletRpc.fetch-nonce requires address string")
        (submit "eth_getTransactionCount" [address "pending"]))

    (fn fetch-gas-price [_self]
        (submit "eth_gasPrice" []))

    (fn estimate-gas [_self opts]
        (local options (or opts {}))
        (local to-address (. options :to))
        (local from-address (. options :from))
        (local value (. options :value))
        (local data (. options :data))
        (assert to-address "WalletRpc.estimate-gas requires :to")
        (assert from-address "WalletRpc.estimate-gas requires :from")
        (local tx {:from from-address
                   :to to-address})
        (when value
            (set (. tx :value) value))
        (when (and data (not (= data "")))
            (set (. tx :data) data))
        (submit "eth_estimateGas" [tx]))

    (fn send-raw-transaction [_self raw]
        (assert raw "WalletRpc.send-raw-transaction requires raw hex")
        (assert (= (type raw) :string) "WalletRpc.send-raw-transaction requires raw string")
        (submit "eth_sendRawTransaction" [raw]))

    {:fetch-balance fetch-balance
     :fetch-nonce fetch-nonce
     :fetch-gas-price fetch-gas-price
     :estimate-gas estimate-gas
     :send-raw-transaction send-raw-transaction
     :poll poll
     :pending-count pending-count
     :wait wait
     :drop drop
     :base-url base-url})

WalletRpc

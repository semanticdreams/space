(local assert-module (require :llm/providers/opencode/assert))
(local assert-callback assert-module.assert-callback)

(fn Config [client]
  (assert client "Config requires an opencode client")

  (fn get [on-response]
    (assert-callback on-response "config.get")
    (client.submit "GET" "/config" {:on_response on-response}))

  (fn update [body on-response]
    (assert-callback on-response "config.update")
    (client.submit "PATCH" "/config"
                   {:body (or body {})
                    :on_response on-response}))

  (fn providers [on-response]
    (assert-callback on-response "config.providers")
    (client.submit "GET" "/config/providers" {:on_response on-response}))

  {:get get
   :update update
   :providers providers})

Config

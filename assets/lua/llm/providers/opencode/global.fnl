(local assert-module (require :llm/providers/opencode/assert))
(local assert-callback assert-module.assert-callback)

(fn Global [client]
  (assert client "Global requires an opencode client")

  (fn health [on-response]
    (assert-callback on-response "global.health")
    (client.submit "GET" "/global/health" {:on_response on-response}))

  {:health health})

Global

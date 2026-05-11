(local assert-module (require :llm/providers/opencode/assert))
(local assert-callback assert-module.assert-callback)

(fn File [client]
  (assert client "File requires an opencode client")

  (fn read [path on-response]
    (assert path "file.read requires a path")
    (assert-callback on-response "file.read")
    (client.submit "GET" "/file"
                   {:query {:path path}
                    :on_response on-response}))

  (fn status [path on-response]
    (assert-callback on-response "file.status")
    (local query (if path {:path path} nil))
    (client.submit "GET" "/file/status"
                   {:query query
                    :on_response on-response}))

  (fn list [on-response]
    (assert-callback on-response "file.list")
    (client.submit "GET" "/file" {:on_response on-response}))

  {:read read
   :status status
   :list list})

File

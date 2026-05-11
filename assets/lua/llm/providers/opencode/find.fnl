(local assert-module (require :llm/providers/opencode/assert))
(local assert-callback assert-module.assert-callback)

(fn Find [client]
  (assert client "Find requires an opencode client")

  (fn text [pattern on-response]
    (assert pattern "find.text requires a pattern")
    (assert-callback on-response "find.text")
    (client.submit "GET" "/find"
                   {:query {:pattern pattern}
                    :on_response on-response}))

  (fn files [query on-response]
    (assert-callback on-response "find.files")
    (local q (or query {}))
    (local params {})
    (when q.query (tset params :query q.query))
    (when q.type_ (tset params :type q.type_))
    (when q.directory (tset params :directory q.directory))
    (when (not (= q.limit nil)) (tset params :limit (tostring q.limit)))
    (client.submit "GET" "/find/file"
                   {:query params
                    :on_response on-response}))

  (fn symbols [query on-response]
    (assert-callback on-response "find.symbols")
    (assert (or (= (type query) "string") (and (= (type query) "table") query.query))
            "find.symbols requires a query string or {:query string}")
    (local q (if (= (type query) "string") query query.query))
    (client.submit "GET" "/find/symbol"
                   {:query {:query q}
                    :on_response on-response}))

  {:text text
   :files files
   :symbols symbols})

Find

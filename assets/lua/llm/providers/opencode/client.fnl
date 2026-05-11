(local json (require :json))
(local HttpCommon (require :http/common))

(local encode-query HttpCommon.encode-query)
(local normalize-headers HttpCommon.normalize-headers)
(local decode-json HttpCommon.decode-json)
(local assert-module (require :llm/providers/opencode/assert))
(local assert-callback assert-module.assert-callback)

(fn Client [opts]
  (local options (or opts {}))
  (local http-binding (or options.http (require :http)))
  (assert http-binding "opencode client requires the http binding")

  (local base-url (string.gsub (or options.base-url "http://127.0.0.1:4096") "/+$" ""))
  (local user-agent (or options.user-agent "space-opencode/1.0"))
  (local default-timeout-ms (or options.timeout-ms 0))
  (local default-connect-timeout-ms (or options.connect-timeout-ms 0))

  (local default-headers {})
  (tset default-headers "Content-Type" "application/json")
  (tset default-headers "Accept" "application/json")

  (fn merge-headers [extra]
    (local merged {})
    (each [k v (pairs default-headers)]
      (tset merged k v))
    (when extra
      (each [k v (pairs extra)]
        (when (not (= v nil))
          (tset merged (tostring k) (tostring v)))))
    merged)

  (fn build-url [path query]
    (.. base-url path (encode-query query)))

  (fn make-result [res]
    (local parsed (decode-json res.body))
    (local headers (normalize-headers res.headers))
    (local ok (and res.ok (< res.status 400)))
    (local status res.status)
    (local parsed-table? (= (type parsed) "table"))
    (fn extract-error [err]
      (if (= (type err) "string") err
          (= (type err) "table") err.message))
    (local error-msg (or (and parsed-table? parsed.error (extract-error parsed.error)) res.error (.. "HTTP " status)))
    {:status status
     :headers headers
     :data (or (and parsed-table? parsed) res.body)
     :raw res.body
     :id res.id
     :ok ok
     :error (if ok nil error-msg)})

  (fn submit [method path request]
    (local on-response request.on_response)
    (assert (= (type on-response) "function") "opencode request requires a function for on_response")
    (local payload (or (and request request.body) nil))
    (when (and (= method "GET") payload (not (= payload "")))
      (error "opencode GET request must not have a body"))
    (local body-str (if payload
                        (if (= (type payload) :string)
                            payload
                            (json.dumps payload))
                        ""))
    (local req-headers (merge-headers (and request request.headers)))
    (local url (build-url path (and request request.query)))
    (http-binding.request
      {:method method
       :url url
       :headers req-headers
       :body body-str
       :user-agent user-agent
       :timeout-ms (or (and request request.timeout-ms) default-timeout-ms)
       :connect-timeout-ms (or (and request request.connect-timeout-ms) default-connect-timeout-ms)
       :callback (fn [res]
                   (on-response (make-result res)))}))

  (fn submit-stream [path request on-chunk]
    (local extra-headers (or (and request request.headers) nil))
    (local req-headers (merge-headers extra-headers))
    (local url (build-url path (or (and request request.query) nil)))
    (set (. req-headers "Accept") "text/event-stream")
    (http-binding.request
      {:method "GET"
       :url url
       :headers req-headers
       :user-agent user-agent
       :stream true
       :timeout-ms (or (and request request.timeout-ms) 0)
       :connect-timeout-ms (or (and request request.connect-timeout-ms) default-connect-timeout-ms)
       :callback (fn [result]
                    (if result.error
                        (on-chunk {:error result.error})
                        result.done
                        (on-chunk {:done true})
                        (on-chunk {:chunk (or result.chunk "")})))}))

  (fn cancel [id]
    (http-binding.cancel id))

  {:submit submit
   :submit-stream submit-stream
   :cancel cancel
   :build-url build-url
   :http-binding (fn [] http-binding)
   :base-url (fn [] base-url)
   :validate-callback assert-callback})

Client

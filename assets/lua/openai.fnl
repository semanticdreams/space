(local json (require :json))
(local HttpCommon (require :http/common))
(local http (require :http))
(local fs (require :fs))
(local appdirs (require :appdirs))
(local logging (require :logging))

(local percent-encode HttpCommon.percent-encode)
(local encode-query HttpCommon.encode-query)
(local normalize-headers HttpCommon.normalize-headers)
(local decode-json HttpCommon.decode-json)

(fn OpenAI [opts]
    (local options (or opts {}))
    (local http-binding (or options.http http))
    (assert http-binding "OpenAI client requires the http binding")
    (assert json "OpenAI client requires the json binding")

    (local log-root (and appdirs (appdirs.user-log-dir "space")))
    (local openai-log-dir
      (and log-root
           (if (and fs fs.join-path)
               (fs.join-path log-root "openai")
               (.. log-root "/openai"))))
    (local openai-log-path
      (and openai-log-dir
           (if (and fs fs.join-path)
               (fs.join-path openai-log-dir "requests.jsonl")
               (.. openai-log-dir "/requests.jsonl"))))

    (fn ensure-openai-log-dir []
      (when (and fs fs.create-dirs openai-log-dir)
        (pcall (fn [] (fs.create-dirs openai-log-dir)))))

    (fn append-log [payload]
      (if (not (and openai-log-path json))
          (when logging
            (logging.warn "[openai] logging unavailable; missing log path or json module"))
          (do
            (ensure-openai-log-dir)
            (pcall (fn []
                     (local handle (io.open openai-log-path "a"))
                     (when handle
                       (handle:write (json.dumps payload) "\n")
                       (handle:close)))))))

    (fn now-iso []
      (os.date "!%Y-%m-%dT%H:%M:%SZ"))

    (local api-key (or options.api_key (os.getenv "OPENAI_API_KEY")))
    (assert api-key "OpenAI API key missing; pass api_key or set OPENAI_API_KEY")

    (local base-url (or options.base_url "https://api.openai.com/v1"))
    (local user-agent (or options.user_agent "space-openai/1.0"))
    (local project (or options.project nil))
    (local organization (or options.organization nil))
    (local beta (or options.beta nil))
    (local default-timeout-ms (or options.timeout_ms 0))
    (local default-connect-timeout-ms (or options.connect_timeout_ms 0))
    (local default-wait (or options.wait_timeout 60))

    (local default-headers {})
    (tset default-headers "Authorization" (.. "Bearer " api-key))
    (tset default-headers "Content-Type" "application/json")
    (tset default-headers "Accept" "application/json")
    (when project
        (set (. default-headers "OpenAI-Project") project))
    (when organization
        (set (. default-headers "OpenAI-Organization") organization))
    (when beta
        (set (. default-headers "OpenAI-Beta") beta))

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
        (local message (or (and parsed parsed.error parsed.error.message) res.error res.body))
        {:status res.status
         :headers headers
         :data (or parsed res.body)
         :raw res.body
         :request_id (or (. headers "request-id") (. headers "x-request-id"))
         :id res.id
         :ok ok
         :error (if ok nil message)})

    (fn submit [method path request]
        (local payload (or (and request request.body) nil))
        (local query (or (and request request.query) nil))
        (local extra-headers (or (and request request.headers) nil))
        (local callback (or (and request request.callback)
                            (and request request.on-response)
                            (and request request.on_response)))
        (assert callback "OpenAI request requires a callback")
        (local stream-flag (and payload (= (type payload) :table) payload.stream))
        (when stream-flag
            (error "Responses streaming via server-sent events is not supported; set stream=false or omit"))
        (local body-str (if payload
                            (if (= (type payload) :string)
                                payload
                                (json.dumps payload))
                            ""))
        (local req-headers (merge-headers extra-headers))
        ;; Tools currently require the beta header; add it automatically when a tools payload is present.
        (when (and (= (type payload) :table) payload.tools (not (. req-headers "OpenAI-Beta")))
            (tset req-headers "OpenAI-Beta" "tools=v1"))
        (local url (build-url path query))
        (local id (http-binding.request {:method method
                                         :url url
                                         :headers req-headers
                                         :body body-str
                                         :user-agent user-agent
                                         :timeout-ms (or (and request request.timeout_ms) default-timeout-ms)
                                         :connect-timeout-ms (or (and request request.connect_timeout_ms) default-connect-timeout-ms)
                                         :callback (fn [res]
                                                       (append-log {:timestamp (now-iso)
                                                                    :event "openai.response"
                                                                    :request_id res.id
                                                                    :status res.status
                                                                    :ok res.ok
                                                                    :error res.error
                                                                    :headers res.headers
                                                                    :body res.body})
                                                       (callback (make-result res)))}))
        (append-log {:timestamp (now-iso)
                     :event "openai.request"
                     :request_id id
                     :method method
                     :url url
                     :headers req-headers
                     :body body-str
                     :timeout_ms (or (and request request.timeout_ms) default-timeout-ms)
                     :connect_timeout_ms (or (and request request.connect_timeout_ms) default-connect-timeout-ms)
                     :user_agent user-agent})
        id)

    (local client {})

    (set client.create-response
         (fn [payload opts]
             (submit "POST" "/responses" {:body payload
                                          :query (or (and opts opts.query) nil)
                                          :headers (or (and opts opts.headers) nil)
                                          :callback (or (and opts opts.callback) (and opts opts.on-response))
                                          :timeout_ms (or (and opts opts.timeout_ms) nil)
                                          :connect_timeout_ms (or (and opts opts.connect_timeout_ms) nil)})))

    (set client.get-response
         (fn [response-id opts]
             (assert response-id "response id is required")
             (submit "GET" (.. "/responses/" (percent-encode (tostring response-id)))
                     {:query (or (and opts opts.query) nil)
                      :headers (or (and opts opts.headers) nil)
                      :callback (or (and opts opts.callback) (and opts opts.on-response))
                      :timeout_ms (or (and opts opts.timeout_ms) nil)
                      :connect_timeout_ms (or (and opts opts.connect_timeout_ms) nil)})))

    (set client.delete-response
         (fn [response-id opts]
             (assert response-id "response id is required")
             (submit "DELETE" (.. "/responses/" (percent-encode (tostring response-id)))
                     {:headers (or (and opts opts.headers) nil)
                      :callback (or (and opts opts.callback) (and opts opts.on-response))
                      :timeout_ms (or (and opts opts.timeout_ms) nil)
                      :connect_timeout_ms (or (and opts opts.connect_timeout_ms) nil)})))

    (set client.list-input-items
         (fn [response-id opts]
             (assert response-id "response id is required")
             (submit "GET" (.. "/responses/" (percent-encode (tostring response-id)) "/input_items")
                     {:query (or (and opts opts.query) nil)
                      :headers (or (and opts opts.headers) nil)
                      :callback (or (and opts opts.callback) (and opts opts.on-response))
                      :timeout_ms (or (and opts opts.timeout_ms) nil)
                      :connect_timeout_ms (or (and opts opts.connect_timeout_ms) nil)})))

    (set client.raw-request
         (fn [method path opts]
             (submit (string.upper method) path opts)))

    (set client.drop
         (fn []))

    client)

OpenAI

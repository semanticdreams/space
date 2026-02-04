(local OpenAI (require :openai))
(local fixtures (require :tests/http-fixtures))

(local fixture-path (app.engine.get-asset-path "lua/tests/data/openai-fixture.json"))
(local fixture (fixtures.read-json fixture-path))
(local json (require :json))

(fn wait-until [pred poll-fn timeout-secs]
  (local deadline (+ (os.clock) (or timeout-secs 2)))
  (while (and (not (pred)) (< (os.clock) deadline))
    (poll-fn 0))
  (pred))

(fn with-client [cb]
  (local install (fixtures.install-mock fixture))
  (var client nil)
  (let [(ok result)
        (pcall
         (fn []
           (set client (OpenAI {:api_key "offline-key"
                                    :user_agent "space-openai-offline/1.0"
                                    :http install.mock.binding}))
           (cb client install.mock)))]
    (when client
      (client.drop))
    (install.restore)
    (if ok
        result
        (error result))))

(fn header-value [headers name]
  (var found nil)
  (if (and (= (type headers) :table) (not (. headers 1)))
      (do
        (each [k v (pairs headers)]
          (when (= (string.lower k) (string.lower name))
            (set found v))))
      (do
        (var idx 1)
        (while (and (not found) (<= idx (# headers)))
          (local pair (. headers idx))
          (var key nil)
          (var value nil)
          (if (and (= (type pair) :table) (. pair 1))
              (do
                (set key (string.lower (. pair 1)))
                (set value (. pair 2)))
              (each [k v (pairs pair)]
                (set key (string.lower k))
                (set value v)))
          (when (and key (= key (string.lower name)))
            (set found value))
          (set idx (+ idx 1)))))
  found)

(fn find-request [requests key method]
  (var found nil)
  (each [_ req (ipairs requests)]
    (when (and (= req.key key)
               (or (not method) (= req.method method)))
      (set found req)))
  found)

(fn fixture-id []
  (local create-entry (find-request fixture.responses "v1/responses" "POST"))
  (when (not create-entry)
    (error "fixture missing create-response entry"))
  (local (ok parsed) (pcall json.loads create-entry.body))
  (when (not ok)
    (error "fixture create-response body not parseable"))
  (or parsed.id (error "fixture create-response missing id")))

(fn assert-output-present [data]
  (local text (or (and data data.output_text) ""))
  (local outputs (or (and data data.output) []))
  (assert (or (> (# text) 0) (> (# outputs) 0)) "response output should not be empty"))

(fn test-create-response []
  (with-client
   (fn [client mock]
     (var resp nil)
     (client.create-response {:model "gpt-4o-mini"
                              :input "hello"
                              :text {:format {:type "text"}}
                              :temperature 0}
                             {:callback (fn [result]
                                          (set resp result))})
     (local ok (wait-until (fn [] resp) mock.binding.poll))
     (assert ok "create-response callback should fire")
     (assert (= resp.status 200))
     (assert resp.data.id)
     (assert-output-present resp.data)
     (assert (or (header-value resp.headers "x-request-id") resp.request_id) "x-request-id should be present")
     (assert (find-request (mock.requests) "v1/responses" "POST") "fixture should record create request")
     resp.data.id)))

(fn test-get-response []
  (with-client
   (fn [client mock]
     (local id (fixture-id))
     (var resp nil)
     (client.get-response id {:callback (fn [result]
                                          (set resp result))})
     (local ok (wait-until (fn [] resp) mock.binding.poll))
     (assert ok "get-response callback should fire")
     (assert (= resp.status 200))
     (assert (= resp.data.id id))
     (assert (or (header-value resp.headers "x-request-id") resp.request_id))
     (assert (find-request (mock.requests) (.. "v1/responses/" id) "GET")))))

(fn test-list-input-items []
  (with-client
   (fn [client mock]
     (local id (fixture-id))
     (var resp nil)
     (client.list-input-items id {:query {:limit 1}
                                  :callback (fn [result]
                                              (set resp result))})
     (local ok (wait-until (fn [] resp) mock.binding.poll))
     (assert ok "list-input-items callback should fire")
     (assert (= resp.status 200))
     (assert resp.data)
     (assert (= resp.data.object "list"))
     (assert (or (header-value resp.headers "x-request-id") resp.request_id))
     (assert (find-request (mock.requests) (.. "v1/responses/" id "/input_items") "GET")))))

(fn test-delete-response []
  (with-client
   (fn [client mock]
     (local id (fixture-id))
     (var resp nil)
     (client.delete-response id {:callback (fn [result]
                                             (set resp result))})
     (local ok (wait-until (fn [] resp) mock.binding.poll))
     (assert ok "delete-response callback should fire")
     (assert (= resp.status 200))
     (assert resp.data.deleted)
     (assert (or (header-value resp.headers "x-request-id") resp.request_id))
     (assert (find-request (mock.requests) (.. "v1/responses/" id) "DELETE")))))

(local tests [{:name "openai create-response fixture" :fn test-create-response}
 {:name "openai get-response fixture" :fn test-get-response}
 {:name "openai list-input-items fixture" :fn test-list-input-items}
 {:name "openai delete-response fixture" :fn test-delete-response}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "openai-offline"
                       :tests tests})))

{:name "openai-offline"
 :tests tests
 :main main}

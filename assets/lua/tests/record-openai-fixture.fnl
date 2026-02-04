(global app {})
(local EngineModule (require :engine))
(set app.engine (EngineModule.Engine {:headless true}))
(local json (require :json))
(local fixtures (require :tests/http-fixtures))
(local OpenAI (require :openai))
(local callbacks (require :callbacks))

(local client (OpenAI {:user_agent "space-openai-record/1.0"}))

(fn wait-until [pred timeout-ms]
  (callbacks.run-loop {:poll-jobs false
                       :poll-http true
                       :sleep-ms 10
                       :timeout-ms (or timeout-ms 60000)
                       :until pred}))

(fn headers->list [tbl]
  (var out [])
  (each [k v (pairs tbl)]
    (table.insert out {k v}))
  out)

(var responses [])

(var create nil)
(client.create-response {:model "gpt-4o-mini"
                         :input "hello from offline fixture"
                         :text {:format {:type "text"}}
                         :temperature 0}
                        {:callback (fn [resp]
                                     (set create resp))})
(local create-ok (wait-until (fn [] create)))
(assert create-ok "create-response callback should fire")
(local resp-id create.data.id)
(table.insert responses {:key "v1/responses"
                         :url "https://api.openai.com/v1/responses"
                         :method "POST"
                         :status create.status
                         :ok true
                         :headers (headers->list create.headers)
                         :body (json.dumps create.data)})

(var got nil)
(client.get-response resp-id {:callback (fn [resp]
                                          (set got resp))})
(local got-ok (wait-until (fn [] got)))
(assert got-ok "get-response callback should fire")
(table.insert responses {:key (.. "v1/responses/" resp-id)
                         :url (.. "https://api.openai.com/v1/responses/" resp-id)
                         :method "GET"
                         :status got.status
                         :ok true
                         :headers (headers->list got.headers)
                         :body (json.dumps got.data)})

(var items nil)
(client.list-input-items resp-id {:query {:limit 1}
                                  :callback (fn [resp]
                                              (set items resp))})
(local items-ok (wait-until (fn [] items)))
(assert items-ok "list-input-items callback should fire")
(table.insert responses {:key (.. "v1/responses/" resp-id "/input_items")
                         :url (.. "https://api.openai.com/v1/responses/" resp-id "/input_items")
                         :method "GET"
                         :status items.status
                         :ok true
                         :headers (headers->list items.headers)
                         :body (json.dumps items.data)})

(var deleted nil)
(client.delete-response resp-id {:callback (fn [resp]
                                             (set deleted resp))})
(local deleted-ok (wait-until (fn [] deleted)))
(assert deleted-ok "delete-response callback should fire")
(table.insert responses {:key (.. "v1/responses/" resp-id)
                         :url (.. "https://api.openai.com/v1/responses/" resp-id)
                         :method "DELETE"
                         :status deleted.status
                         :ok true
                         :headers (headers->list deleted.headers)
                         :body (json.dumps deleted.data)})

(fixtures.write-json! (app.engine.get-asset-path "lua/tests/data/openai-fixture.json")
                      {:name "openai-offline"
                       :recorded_at (os.date "!%Y-%m-%dT%H:%M:%SZ")
                       :base_url "https://api.openai.com/v1"
                       :responses responses})

(client.drop)
(print "Recorded OpenAI fixture" resp-id)

(local json (require :json))
(local fixtures (require :tests/http-fixtures))
(local OpenAI (require :openai))
(local callbacks (require :callbacks))

(local client (OpenAI {:user_agent "space-openai-record-tools/1.0"}))

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

(fn parse-tool-call [resp tool-name]
  (local output (or (and resp resp.data resp.data.output) []))
  (var found nil)
  (each [_ item (ipairs output)]
    (when (and (= item.type "function_call") (= item.name tool-name))
      (set found item))
    (when (and (= item.type "message") item.tool_calls)
      (each [_ call (ipairs item.tool_calls)]
        (local call-name (or (and call call.function call.function.name) call.name))
        (when (and call-name (= call-name tool-name))
          (set found {:id (or call.id call.call_id)
                      :call_id (or call.call_id call.id)
                      :name call-name
                      :arguments (or (and call call.function call.function.arguments) call.arguments)})))))
  found)

(fn parse-args [call]
  (local args-json (or (and call call.arguments) ""))
  (local (ok parsed) (pcall json.loads args-json))
  (assert ok "tool call arguments should be valid JSON")
  parsed)

(var responses [])

(local tool-name "local_uppercase")
(local tool-spec [{:type "function"
                   :name tool-name
                   :description "Uppercase the provided text."
                   :parameters {:type "object"
                                :properties {:text {:type "string"
                                                    :description "Text to uppercase"}}
                                :required ["text"]
                                :additionalProperties false}}])

(var create nil)
(client.create-response {:model "gpt-4o-mini"
                         :input [{:role "user"
                                  :content "Call the local_uppercase tool with the phrase \"space missions\" and wait for the tool output."}]
                         :tools tool-spec
                         :tool_choice {:type "function"
                                       :name tool-name}
                         :parallel_tool_calls false
                         :text {:format {:type "text"}}
                         :temperature 0}
                        {:callback (fn [resp]
                                     (set create resp))})
(local create-ok (wait-until (fn [] create)))
(assert create-ok "tool create-response callback should fire")

(table.insert responses {:key "v1/responses"
                         :url "https://api.openai.com/v1/responses"
                         :method "POST"
                         :status create.status
                         :ok true
                         :headers (headers->list create.headers)
                         :body (json.dumps create.data)})

(local fn-call (parse-tool-call create tool-name))
(assert fn-call "recorded response missing tool call")
(local args (parse-args fn-call))
(local text (or args.text args.message args.content ""))
(local tool-output (string.upper text))

(var follow nil)
(client.create-response {:model "gpt-4o-mini"
                         :input [{:role "user"
                                  :content (.. "The tool " tool-name " returned \"" tool-output "\". Respond with that exact text and nothing else.")}]
                         :text {:format {:type "text"}}
                         :temperature 0}
                        {:callback (fn [resp]
                                     (set follow resp))})
(local follow-ok (wait-until (fn [] follow)))
(assert follow-ok "follow-up create-response callback should fire")

(table.insert responses {:key "v1/responses"
                         :url "https://api.openai.com/v1/responses"
                         :method "POST"
                         :status follow.status
                         :ok true
                         :headers (headers->list follow.headers)
                         :body (json.dumps follow.data)})

(local first-id create.data.id)
(local second-id follow.data.id)

(var deleted-first nil)
(var deleted-second nil)
(client.delete-response first-id {:callback (fn [resp]
                                             (set deleted-first resp))})
(client.delete-response second-id {:callback (fn [resp]
                                              (set deleted-second resp))})
(local deleted-first-ok (wait-until (fn [] deleted-first)))
(local deleted-second-ok (wait-until (fn [] deleted-second)))
(assert deleted-first-ok "delete-response first callback should fire")
(assert deleted-second-ok "delete-response second callback should fire")

(table.insert responses {:key (.. "v1/responses/" first-id)
                         :url (.. "https://api.openai.com/v1/responses/" first-id)
                         :method "DELETE"
                         :status deleted-first.status
                         :ok true
                         :headers (headers->list deleted-first.headers)
                         :body (json.dumps {:deleted true :id first-id :object "response.deleted"})})

(table.insert responses {:key (.. "v1/responses/" second-id)
                         :url (.. "https://api.openai.com/v1/responses/" second-id)
                         :method "DELETE"
                         :status deleted-second.status
                         :ok true
                         :headers (headers->list deleted-second.headers)
                         :body (json.dumps {:deleted true :id second-id :object "response.deleted"})})

(local fixture-path (.. (os.getenv "PWD") "/assets/lua/tests/data/openai-tools-fixture.json"))

(fixtures.write-json! fixture-path
                      {:name "openai-tools-offline"
                       :recorded_at (os.date "!%Y-%m-%dT%H:%M:%SZ")
                       :base_url "https://api.openai.com/v1"
                       :responses responses})

(client.drop)
(print "Recorded OpenAI tools fixture" first-id second-id "->" fixture-path)

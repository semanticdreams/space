(local json (require :json))
(local callbacks (require :callbacks))

(var client nil)
(var created-id nil)

(fn wait-until [pred timeout-ms]
    (callbacks.run-loop {:poll-jobs false
                         :poll-http true
                         :sleep-ms 10
                         :timeout-ms (or timeout-ms 60000)
                         :until pred}))

(fn ensure-client []
    (when (not client)
        (local OpenAI (require :openai))
        (set client (OpenAI {:timeout_ms 60000
                             :connect_timeout_ms 10000
                             :user_agent "space-openai-test/1.0"}))))

(fn assert-output-present [data]
    (local text (or (and data data.output_text) ""))
    (local outputs (or (and data data.output) []))
    (assert (or (> (# text) 0) (> (# outputs) 0)) "response output should not be empty"))

(fn find-function-call [output target-name]
    (var found nil)
    (when (and output (= (type output) :table))
        (each [_ item (ipairs output)]
            (when (and (= item.type "function_call") (= item.name target-name))
                (set found item))
            (when (and (= item.type "message") item.tool_calls)
                (each [_ call (ipairs item.tool_calls)]
                    (local call-name (or (and call call.function call.function.name) call.name))
                    (when (and call-name (= call-name target-name))
                        (set found {:id (or call.id call.call_id)
                                    :call_id (or call.call_id call.id)
                                    :name call-name
                                    :arguments (or (and call call.function call.function.arguments) call.arguments)}))))))
    found)

(fn parse-tool-args [call]
    (local args-json (or (and call call.arguments) ""))
    (local (ok parsed) (pcall json.loads args-json))
    (assert ok "tool call arguments should be valid JSON")
    parsed)

(fn collect-output-text [data]
    (if (and data data.output_text (> (# data.output_text) 0))
        data.output_text
        (let [pieces []]
            (when (and data data.output)
                (each [_ item (ipairs data.output)]
                    (when (= item.type "message")
                        (each [_ content (ipairs (or item.content []))]
                            (when (= content.type "output_text")
                                (table.insert pieces content.text))))
                    (when (= item.type "output_text")
                        (table.insert pieces item.text))))
            (table.concat pieces " "))))

(fn await-delete-response [resp-id]
    (var deleted nil)
    (client.delete-response resp-id {:callback (fn [resp]
                                                 (set deleted resp))})
    (wait-until (fn [] deleted) 20000)
    deleted)

(fn delete-response-safe [resp-id]
    (when resp-id
        (pcall (fn []
                    (await-delete-response resp-id)))))

(fn test-local-tools-roundtrip []
    (ensure-client)
    (local tool-name "local_uppercase")
    (local tool-spec [{:type "function"
                       :name tool-name
                       :description "Uppercase the provided text."
                       :parameters {:type "object"
                                    :properties {:text {:type "string"
                                                        :description "Text to uppercase"}}
                                    :required ["text"]
                                    :additionalProperties false}}])
    (var request nil)
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
                                         (set request resp))})
    (local ok (wait-until (fn [] request)))
    (assert ok "tool-call create-response callback should fire")
    (assert (= request.status 200) "tool-call create-response should return HTTP 200")
    (assert request.data.id "tool-call create-response should include id")
    (local fn-call (find-function-call request.data.output tool-name))
    (assert fn-call "model should request the local tool")
    (local args (parse-tool-args fn-call))
    (local input-text (or args.text args.message args.content))
    (assert input-text "tool arguments should include text")
    (local tool-output (string.upper input-text))
    (var follow-up nil)
    (client.create-response {:model "gpt-4o-mini"
                             :input [{:role "user"
                                      :content (.. "The tool " tool-name " returned \"" tool-output "\". Respond with that exact text and nothing else.")}]
                             :text {:format {:type "text"}}
                             :temperature 0}
                            {:callback (fn [resp]
                                         (set follow-up resp))})
    (local follow-ok (wait-until (fn [] follow-up)))
    (assert follow-ok "follow-up callback should fire")
    (assert (= follow-up.status 200) "follow-up create-response should return HTTP 200")
    (local final-text (collect-output-text follow-up.data))
    (assert (string.find (string.lower final-text) (string.lower tool-output))
            "final response should include tool output")
    (delete-response-safe request.data.id)
    (delete-response-safe follow-up.data.id))

(fn test-create-response []
    (ensure-client)
    (var resp nil)
    (client.create-response {:model "gpt-4o-mini"
                             :input "Reply with a short greeting in five words or fewer."
                             :text {:format {:type "text"}}
                             :temperature 0}
                            {:callback (fn [result]
                                         (set resp result))})
    (local ok (wait-until (fn [] resp)))
    (assert ok "create-response callback should fire")
    (assert (= resp.status 200) "create-response should return HTTP 200")
    (assert resp.data "create-response should parse JSON")
    (assert resp.data.id "create-response should include id")
    (set created-id resp.data.id)
    (assert-output-present resp.data)
    resp.data.id)

(fn test-get-response []
    (ensure-client)
    (assert created-id "response id missing from create test")
    (var fetched nil)
    (client.get-response created-id {:callback (fn [result]
                                                 (set fetched result))})
    (local ok (wait-until (fn [] fetched)))
    (assert ok "get-response callback should fire")
    (assert (= fetched.status 200) "get-response should return HTTP 200")
    (assert (= fetched.data.id created-id) "get-response should echo requested id")
    (assert-output-present fetched.data))

(fn test-list-input-items []
    (ensure-client)
    (assert created-id "response id missing from create test")
    (var items nil)
    (client.list-input-items created-id {:query {:limit 1 :order "desc"}
                                         :callback (fn [result]
                                                     (set items result))})
    (local ok (wait-until (fn [] items)))
    (assert ok "list-input-items callback should fire")
    (assert (= items.status 200) "list-input-items should return HTTP 200")
    (assert items.data "list-input-items should include parsed data")
    (assert (= items.data.object "list") "list-input-items should return list object")
    (assert (>= (# items.data.data) 1) "list-input-items should return at least one item"))

(fn test-delete-response []
    (ensure-client)
    (assert created-id "response id missing from create test")
    (var deleted nil)
    (client.delete-response created-id {:callback (fn [result]
                                                    (set deleted result))})
    (local ok (wait-until (fn [] deleted)))
    (assert ok "delete-response callback should fire")
    (assert (= deleted.status 200) "delete-response should return HTTP 200")
    (assert deleted.data.deleted "delete-response should mark response as deleted"))

(local tests [{:name "local tools roundtrip" :fn test-local-tools-roundtrip}
              {:name "create-response" :fn test-create-response}
              {:name "get-response" :fn test-get-response}
              {:name "list-input-items" :fn test-list-input-items}
              {:name "delete-response" :fn test-delete-response}])

(fn teardown []
    (when client
        (client.drop)))

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "openai-online"
                           :tests tests
                           :teardown teardown})))

{:name "openai-online"
 :tests tests
 :main main}

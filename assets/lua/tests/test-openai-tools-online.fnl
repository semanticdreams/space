(local LlmTools (require :llm/tools/init))
(local json (require :json))
(local callbacks (require :callbacks))

(var client nil)

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
                             :user_agent "space-openai-tools-online/1.0"}))))

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

(fn test-openai-list-dir-schema []
    (ensure-client)
    (var request nil)
    (client.create-response {:model "gpt-4o-mini"
                             :input [{:role "user"
                                      :content "Call the list_dir tool for /tmp and wait."}]
                             :tools (LlmTools.openai-tools)
                             :tool_choice {:type "function"
                                           :name "list_dir"}
                             :parallel_tool_calls false
                             :text {:format {:type "text"}}
                             :temperature 0}
                            {:callback (fn [resp]
                                         (set request resp))})
    (local ok (wait-until (fn [] request)))
    (assert ok "list_dir callback should fire")
    (assert (= request.status 200) "create-response with list_dir tool should return HTTP 200")
    (local fn-call (find-function-call request.data.output "list_dir"))
    (assert fn-call "model should request list_dir tool")
    (local args (parse-tool-args fn-call))
    (assert (or (= args.include_hidden true) (= args.include_hidden false))
            "list_dir call should include include_hidden boolean")
    (assert (or args.directory args.path) "list_dir call should include directory"))

(local tests [{:name "openai list_dir schema" :fn test-openai-list-dir-schema}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "openai-tools-online"
                       :tests tests})))

{:name "openai-tools-online"
 :tests tests
 :main main}

(local OpenAI (require :openai))
(local fixtures (require :tests/http-fixtures))
(local json (require :json))

(local fixture-path (.. (os.getenv "PWD") "/assets/lua/tests/data/openai-tools-fixture.json"))
(local fixture (fixtures.read-json fixture-path))

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
                                        :user_agent "space-openai-tools-offline/1.0"
                                        :http install.mock.binding}))
               (cb client install.mock)))]
        (when client
            (client.drop))
        (install.restore)
        (if ok
            result
            (error result))))

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

(fn test-local-tools-offline []
    (with-client
     (fn [client mock]
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
                                 {:callback (fn [result]
                                              (set request result))})
         (local ok (wait-until (fn [] request) mock.binding.poll))
         (assert ok "tool call callback should fire")
         (assert (= request.status 200))
         (local fn-call (find-function-call request.data.output tool-name))
         (assert fn-call "model should request the local tool (fixture)")
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
                                 {:callback (fn [result]
                                              (set follow-up result))})
         (local follow-ok (wait-until (fn [] follow-up) mock.binding.poll))
         (assert follow-ok "follow-up callback should fire")
         (assert (= follow-up.status 200))
         (local final-text (collect-output-text follow-up.data))
         (assert (string.find (string.lower final-text) (string.lower tool-output)))
         (assert (>= (# (mock.requests)) 2) "fixture should record both create requests"))))

(local tests [{:name "openai local tools fixture" :fn test-local-tools-offline}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "openai-tools-offline"
                       :tests tests})))

{:name "openai-tools-offline"
 :tests tests
 :main main}

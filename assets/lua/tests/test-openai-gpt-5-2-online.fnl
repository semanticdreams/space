(local callbacks (require :callbacks))
(local LlmRequests (require :llm/requests))
(local LlmStore (require :llm/store))
(local fs (require :fs))

(var client nil)

(fn wait-until [pred timeout-ms]
    (callbacks.run-loop {:poll-jobs false
                         :poll-http true
                         :sleep-ms 10
                         :timeout-ms (or timeout-ms 120000)
                         :until pred}))

(fn ensure-client []
    (when (not client)
        (local OpenAI (require :openai))
        (set client (OpenAI {:timeout_ms 120000
                             :connect_timeout_ms 15000
                             :user_agent "space-openai-gpt-5.2-online/1.0"}))))

(fn await-delete-response [resp-id]
    (var deleted nil)
    (client.delete-response resp-id {:callback (fn [resp]
                                                 (set deleted resp))})
    (wait-until (fn [] deleted) 30000)
    deleted)

(fn delete-response-safe [resp-id]
    (when resp-id
        (pcall (fn []
                    (await-delete-response resp-id)))))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "openai-gpt-5-2-online"))

(fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "openai-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
    (local dir (make-temp-dir))
    (when (fs.exists dir)
        (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result) (pcall f dir))
    (fs.remove-all dir)
    (if ok
        result
        (error result)))

(fn run-gpt-5-2-request [store convo]
    (var captured nil)
    (local openai {})
    (set openai.create-response
         (fn [payload opts]
             (set captured payload)
             (client.create-response payload opts)))
    (var finished nil)
    (LlmRequests.run-request store convo.id {:openai openai
                                             :tools false
                                             :input-items [{:role "user"
                                                            :content "Reply with exactly: OK"}]
                                             :on-finish (fn [payload]
                                                            (set finished payload))})
    (local ok (wait-until (fn [] finished)))
    (assert ok "gpt-5.2 request should finish")
    (assert (and finished finished.ok) "gpt-5.2 request should succeed")
    {:captured captured
     :finished finished})

(fn gpt-5-2-test-body [root]
    (local store (LlmStore.Store {:base-dir root}))
    (local convo (store:create-conversation {:name "gpt-5.2 online"
                                             :model "gpt-5.2"
                                             :temperature 0.7
                                             :reasoning_effort "high"
                                             :text_verbosity "low"}))
    (local result (run-gpt-5-2-request store convo))
    (local captured result.captured)
    (local finished result.finished)
    (assert captured "gpt-5.2 request should capture payload")
    (assert (= (and captured.reasoning captured.reasoning.effort) "high")
            "payload should include reasoning effort")
    (assert (= (and captured.text captured.text.verbosity) "low")
            "payload should include text verbosity")
    (assert (= captured.temperature nil)
            "payload should omit temperature when effort is not none")
    (local resp-id (and finished finished.response finished.response.data finished.response.data.id))
    (delete-response-safe resp-id))

(fn test-gpt-5-2-reasoning-effort-and-verbosity []
    (ensure-client)
    (with-temp-dir gpt-5-2-test-body))

(local tests [{:name "gpt-5.2 reasoning effort and verbosity" :fn test-gpt-5-2-reasoning-effort-and-verbosity}])

(fn teardown []
    (when client
        (client.drop)))

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "openai-gpt-5-2-online"
                           :tests tests
                           :teardown teardown})))

{:name "openai-gpt-5-2-online"
 :tests tests
 :main main}

(local tests [])
(local fs (require :fs))
(local json (require :json))
(local callbacks (require :callbacks))
(local CodexSdk (require :codex-sdk))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "codex-sdk"))
(local fake-codex-path (fs.absolute "scripts/fake-codex-cli.py"))

(fn normalize-eol [s]
  (if s
      (string.gsub s "\r\n" "\n")
      ""))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "codex-sdk-" (os.time) "-" temp-counter)))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn read-log [path]
  (json.loads (fs.read-file path)))

(fn base-client [log-path extra-env]
  (local env {:FAKE_CODEX_LOG log-path
              :FAKE_CODEX_SCENARIO "success"
              :PATH (or (os.getenv "PATH") "")})
  (each [k v (pairs (or extra-env {}))]
    (tset env k v))
  (CodexSdk.Codex {:codex-path fake-codex-path
                   :base-url "https://example.test/v1"
                   :api-key "sdk-test-key"
                   :env env
                   :clear-env true}))

(fn base-client-with-options [log-path extra-env options]
  (local env {:FAKE_CODEX_LOG log-path
              :FAKE_CODEX_SCENARIO "success"
              :PATH (or (os.getenv "PATH") "")})
  (each [k v (pairs (or extra-env {}))]
    (tset env k v))
  (local opts (or options {}))
  (tset opts :codex-path fake-codex-path)
  (tset opts :env env)
  (when (= opts.base-url nil)
    (tset opts :base-url "https://example.test/v1"))
  (when (= opts.api-key nil)
    (tset opts :api-key "sdk-test-key"))
  (CodexSdk.Codex opts))

(fn codex-run-returns-summary-and-logs-options []
  (with-temp-dir
    (fn [dir]
      (local log-path (fs.join-path dir "request.json"))
      (local client (base-client log-path nil))
      (local thread (client:start-thread {:model "gpt-test-1"
                                          :sandbox-mode "workspace-write"
                                          :working-directory dir
                                          :additional-directories ["/tmp/add-a" "/tmp/add-b"]
                                          :skip-git-repo-check true
                                          :model-reasoning-effort "high"
                                          :network-access-enabled true
                                          :web-search-mode "live"
                                          :approval-policy "never"}))
      (local result
        (thread:run [{:type :text :text "hello world"}
                     {:type :local-image :path "/tmp/a.png"}
                     {:type :local-image :path "/tmp/b.png"}]
                    {:output-schema {:type "object"
                                     :properties {:answer {:type "string"}}
                                     :required ["answer"]
                                     :additionalProperties false}}))
      (assert (= thread.id "thread_fake_123"))
      (assert (= result.final-response "Hi!"))
      (assert (= result.usage.input-tokens 42))
      (assert (= result.usage.cached-input-tokens 12))
      (assert (= result.usage.output-tokens 5))
      (assert (= (. (. result.items 1) :type) :agent-message))
      (local logged (read-log log-path))
      (assert (= logged.stdin "hello world"))
      (assert (= logged.env.OPENAI_BASE_URL "https://example.test/v1"))
      (assert (= logged.env.CODEX_API_KEY "sdk-test-key"))
      (assert (= logged.env.CODEX_INTERNAL_ORIGINATOR_OVERRIDE "codex_sdk_fennel"))
      (assert (= (. logged.argv 1) "exec"))
      (assert (= (. logged.argv 2) "--experimental-json"))
      (assert (not (= nil (string.find (table.concat logged.argv " ") "--model gpt-test-1" 1 true))))
      (assert (not (= nil (string.find (table.concat logged.argv " ") "--sandbox workspace-write" 1 true))))
      (assert (not (= nil (string.find (table.concat logged.argv " ") "--skip-git-repo-check" 1 true))))
      (assert (not (= nil (string.find (table.concat logged.argv " ") "--image /tmp/a.png" 1 true))))
      (assert (not (= nil (string.find (table.concat logged.argv " ") "--image /tmp/b.png" 1 true))))
      (assert (not (= nil (string.find (table.concat logged.argv " ") "--output-schema" 1 true)))))))

(fn codex-resume-thread-passes-resume-id []
  (with-temp-dir
    (fn [dir]
      (local log-path (fs.join-path dir "resume.json"))
      (local client (base-client log-path {:FAKE_CODEX_MESSAGE "Second"}))
      (local thread (client:resume-thread "thread_resume_42"))
      (local result (thread:run "resume"))
      (assert (= result.final-response "Second"))
      (assert (= thread.id "thread_resume_42"))
      (local logged (read-log log-path))
      (assert (not (= nil (string.find (table.concat logged.argv " ") "resume thread_resume_42" 1 true)))))))

(fn codex-web-search-enabled-falls-back-to-config []
  (with-temp-dir
    (fn [dir]
      (local log-path (fs.join-path dir "web-search.json"))
      (local client (base-client log-path nil))
      (local thread (client:start-thread {:web-search-enabled false}))
      (thread:run "legacy web search")
      (local logged (read-log log-path))
      (assert (not (= nil (string.find (table.concat logged.argv " ") "web_search=\"disabled\"" 1 true)))))))

(fn codex-originator-override-is-respected []
  (with-temp-dir
    (fn [dir]
      (local log-path (fs.join-path dir "originator.json"))
      (local client
        (base-client-with-options log-path nil {:originator "custom_originator"}))
      (local thread (client:start-thread))
      (thread:run "originator")
      (local logged (read-log log-path))
      (assert (= logged.env.CODEX_INTERNAL_ORIGINATOR_OVERRIDE "custom_originator")))))

(fn codex-clear-env-false-preserves-parent-env []
  (with-temp-dir
    (fn [dir]
      (local log-path (fs.join-path dir "clear-env.json"))
      (local client
        (base-client-with-options log-path nil {:clear-env false}))
      (local thread (client:start-thread))
      (thread:run "clear env")
      (local logged (read-log log-path))
      (assert (= logged.env.CODEX_API_KEY "sdk-test-key"))
      (assert (= logged.env.OPENAI_BASE_URL "https://example.test/v1")))))

(fn codex-output-schema-rejects-non-object []
  (with-temp-dir
    (fn [dir]
      (local client (base-client (fs.join-path dir "schema.json") nil))
      (local thread (client:start-thread))
      (local (ok err) (pcall (fn [] (thread:run "bad schema" {:output-schema ["not-an-object"]}))))
      (assert (not ok))
      (assert (not (= nil (string.find err "plain JSON object" 1 true)))))))

(fn codex-output-schema-rejects-numeric-keys []
  (with-temp-dir
    (fn [dir]
      (local client (base-client (fs.join-path dir "schema-numeric.json") nil))
      (local thread (client:start-thread))
      (local (ok err)
        (pcall
          (fn []
            (thread:run "bad schema"
                        {:output-schema {:type "object"
                                         [2] "bad"}}))))
      (assert (not ok))
      (assert (not (= nil (string.find err "plain JSON object" 1 true)))))))

(fn codex-on-error-callback-fires-for-process-failure []
  (with-temp-dir
    (fn [dir]
      (local client (base-client (fs.join-path dir "on-error.json")
                                 {:FAKE_CODEX_SCENARIO "exit_error"}))
      (local thread (client:start-thread))
      (var callback-error nil)
      (local handle
        (thread:run-streamed
          "fail"
          {:on-error (fn [err]
                       (set callback-error err))}))
      (local (ok _err) (pcall (fn [] (handle:wait))))
      (assert (not ok))
      (assert callback-error)
      (assert (not (= nil (string.find callback-error.message "simulated process failure" 1 true)))))))

(fn codex-handle-wait-is-idempotent-after-success []
  (with-temp-dir
    (fn [dir]
      (local client (base-client (fs.join-path dir "idempotent.json") nil))
      (local thread (client:start-thread))
      (local handle (thread:run-streamed "idempotent"))
      (local first (handle:wait))
      (local second (handle:wait))
      (assert (= first.final-response "Hi!"))
      (assert (= second.final-response "Hi!"))
      (assert (= handle.finished true))
      (assert (= (handle:poll) true)))))

(fn codex-run-throws-on-turn-failed []
  (with-temp-dir
    (fn [dir]
      (local client (base-client (fs.join-path dir "failed.json")
                                 {:FAKE_CODEX_SCENARIO "turn_failed"}))
      (local thread (client:start-thread))
      (local (ok err) (pcall (fn [] (thread:run "fail"))))
      (assert (not ok))
      (assert (not (= nil (string.find err "simulated turn failure" 1 true)))))))

(fn codex-run-throws-on-malformed-json []
  (with-temp-dir
    (fn [dir]
      (local client (base-client (fs.join-path dir "malformed.json")
                                 {:FAKE_CODEX_SCENARIO "malformed"}))
      (local thread (client:start-thread))
      (local (ok err) (pcall (fn [] (thread:run "bad"))))
      (assert (not ok))
      (assert (not (= nil (string.find err "Failed to parse item" 1 true)))))))

(fn codex-run-streamed-poll-cleans-up-on-malformed-json []
  (with-temp-dir
    (fn [dir]
      (local client (base-client (fs.join-path dir "malformed-stream.json")
                                 {:FAKE_CODEX_SCENARIO "malformed"}))
      (local thread (client:start-thread))
      (var callback-error nil)
      (local handle
        (thread:run-streamed
          "bad"
          {:on-error (fn [err]
                       (set callback-error err))}))
      (local (ok err)
        (pcall
          (fn []
            (callbacks.run-loop {:poll-jobs false
                                 :poll-http false
                                 :poll-process false
                                 :sleep-ms 1
                                 :timeout-ms 1000
                                 :until (fn []
                                          (local done (handle:poll))
                                          (not (not done)))}))))
      (assert (not ok))
      (assert (not (= nil (string.find err "Failed to parse item" 1 true))))
      (assert callback-error)
      (assert (= thread.active-turn nil))
      (assert (= handle.finished true)))))

(fn codex-run-throws-on-process-error []
  (with-temp-dir
    (fn [dir]
      (local client (base-client (fs.join-path dir "exit.json")
                                 {:FAKE_CODEX_SCENARIO "exit_error"}))
      (local thread (client:start-thread))
      (local (ok err) (pcall (fn [] (thread:run "bad exit"))))
      (assert (not ok))
      (assert (not (= nil (string.find err "simulated process failure" 1 true)))))))

(fn codex-run-streamed-emits-events-before-completion []
  (with-temp-dir
    (fn [dir]
      (local client (base-client (fs.join-path dir "stream.json")
                                 {:FAKE_CODEX_SCENARIO "slow_stream"
                                  :FAKE_CODEX_MESSAGE "Streamed"}))
      (local thread (client:start-thread))
      (local event-types [])
      (var completed nil)
      (var callback-error nil)
      (local handle
        (thread:run-streamed
          "stream"
          {:on-event (fn [event]
                       (table.insert event-types event.type))
           :on-complete (fn [result]
                          (set completed result))
           :on-error (fn [err]
                       (set callback-error err))}))
      (local saw-early
        (callbacks.run-loop {:poll-jobs false
                             :poll-http false
                             :poll-process false
                             :sleep-ms 1
                             :timeout-ms 2000
                             :until (fn []
                                      (handle:poll)
                                      (>= (length event-types) 2))}))
      (assert saw-early "should observe streamed events before completion")
      (assert (handle:running?) "handle should still be running while early events are observed")
      (local result (handle:wait))
      (assert (= callback-error nil))
      (assert (= result.final-response "Streamed"))
      (assert (= completed.final-response "Streamed"))
      (assert (= (. event-types 1) :thread-started))
      (assert (= (. event-types 2) :turn-started))
      (assert (>= (length event-types) 5)))))

(fn codex-run-preserves-unknown-item []
  (with-temp-dir
    (fn [dir]
      (local client (base-client (fs.join-path dir "unknown.json")
                                 {:FAKE_CODEX_SCENARIO "unknowns"
                                  :FAKE_CODEX_MESSAGE "Known"}))
      (local thread (client:start-thread))
      (local result (thread:run "unknowns"))
      (local first-item (. result.items 1))
      (assert (= first-item.type :unknown-item))
      (assert (= (. first-item.raw :type) "mystery_item"))
      (assert (= result.final-response "Known")))))

(fn codex-run-streamed-preserves-unknown-event []
  (with-temp-dir
    (fn [dir]
      (local client (base-client (fs.join-path dir "unknown-event.json")
                                 {:FAKE_CODEX_SCENARIO "unknowns"
                                  :FAKE_CODEX_MESSAGE "Known"}))
      (local thread (client:start-thread))
      (var unknown-event nil)
      (local handle
        (thread:run-streamed
          "unknown event"
          {:on-event (fn [event]
                       (when (= event.type :unknown-event)
                         (set unknown-event event)))}))
      (local result (handle:wait))
      (assert unknown-event "stream should surface unknown event")
      (assert (= (. unknown-event.raw :type) "mystery.event"))
      (assert (= result.final-response "Known")))))

(fn codex-stream-cancel-clears-active-turn []
  (with-temp-dir
    (fn [dir]
      (local client (base-client (fs.join-path dir "cancel.json")
                                 {:FAKE_CODEX_SCENARIO "cancel_wait"}))
      (local thread (client:start-thread))
      (var callback-error nil)
      (local handle
        (thread:run-streamed
          "cancel me"
          {:on-error (fn [err]
                       (set callback-error err))}))
      (local saw-start
        (callbacks.run-loop {:poll-jobs false
                             :poll-http false
                             :poll-process false
                             :sleep-ms 1
                             :timeout-ms 1000
                             :until (fn []
                                      (handle:poll)
                                      (handle:running?))}))
      (assert saw-start "cancel test should reach running state")
      (handle:cancel)
      (local (ok err) (pcall (fn [] (handle:wait))))
      (assert (not ok) "cancelled handle wait should fail")
      (assert callback-error "cancelled stream should report on-error")
      (assert (= thread.active-turn nil) "active turn should clear after cancellation")
      (local success-client (base-client (fs.join-path dir "after-cancel.json") nil))
      (local success-thread (success-client:start-thread))
      (local next-result (success-thread:run "after cancel"))
      (assert (= next-result.final-response "Hi!")))))

(fn codex-thread-rejects-concurrent-turns []
  (with-temp-dir
    (fn [dir]
      (local client (base-client (fs.join-path dir "concurrent.json")
                                 {:FAKE_CODEX_SCENARIO "cancel_wait"}))
      (local thread (client:start-thread))
      (local handle (thread:run-streamed "first"))
      (local saw-running
        (callbacks.run-loop {:poll-jobs false
                             :poll-http false
                             :poll-process false
                             :sleep-ms 1
                             :timeout-ms 1000
                             :until (fn []
                                      (handle:poll)
                                      (handle:running?))}))
      (assert saw-running "stream should be running before concurrent check")
      (local (ok err) (pcall (fn [] (thread:run "second"))))
      (assert (not ok))
      (assert (not (= nil (string.find err "one active turn" 1 true))))
      (handle:cancel)
      (pcall (fn [] (handle:wait))))))

(table.insert tests {:name "codex-sdk run returns summary and logs argv/env" :fn codex-run-returns-summary-and-logs-options})
(table.insert tests {:name "codex-sdk resume-thread passes resume id" :fn codex-resume-thread-passes-resume-id})
(table.insert tests {:name "codex-sdk web-search-enabled falls back to config" :fn codex-web-search-enabled-falls-back-to-config})
(table.insert tests {:name "codex-sdk originator override is respected" :fn codex-originator-override-is-respected})
(table.insert tests {:name "codex-sdk clear-env false preserves parent env path" :fn codex-clear-env-false-preserves-parent-env})
(table.insert tests {:name "codex-sdk output schema rejects non object" :fn codex-output-schema-rejects-non-object})
(table.insert tests {:name "codex-sdk output schema rejects numeric keys" :fn codex-output-schema-rejects-numeric-keys})
(table.insert tests {:name "codex-sdk on-error callback fires for process failure" :fn codex-on-error-callback-fires-for-process-failure})
(table.insert tests {:name "codex-sdk handle wait is idempotent after success" :fn codex-handle-wait-is-idempotent-after-success})
(table.insert tests {:name "codex-sdk run throws on turn failed" :fn codex-run-throws-on-turn-failed})
(table.insert tests {:name "codex-sdk run throws on malformed json" :fn codex-run-throws-on-malformed-json})
(table.insert tests {:name "codex-sdk run-streamed poll cleans up on malformed json" :fn codex-run-streamed-poll-cleans-up-on-malformed-json})
(table.insert tests {:name "codex-sdk run throws on process error" :fn codex-run-throws-on-process-error})
(table.insert tests {:name "codex-sdk run-streamed emits events incrementally" :fn codex-run-streamed-emits-events-before-completion})
(table.insert tests {:name "codex-sdk run preserves unknown item" :fn codex-run-preserves-unknown-item})
(table.insert tests {:name "codex-sdk run-streamed preserves unknown event" :fn codex-run-streamed-preserves-unknown-event})
(table.insert tests {:name "codex-sdk stream cancel clears active turn" :fn codex-stream-cancel-clears-active-turn})
(table.insert tests {:name "codex-sdk thread rejects concurrent turns" :fn codex-thread-rejects-concurrent-turns})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "codex-sdk"
                       :tests tests})))

{:name "codex-sdk"
 :tests tests
 :main main}

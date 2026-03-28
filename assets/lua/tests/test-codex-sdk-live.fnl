(local json (require :json))
(local fs (require :fs))
(local CodexSdk (require :llm/providers/codex))
(local tempfile (require :tempfile))

(local tests [])
(local run-live (= (os.getenv "CODEX_SDK_RUN_LIVE") "1"))
(local callbacks (require :callbacks))

(fn should-skip? []
  (not run-live))

(fn print-skip [name]
  (print (.. "[SKIP] " name " (set CODEX_SDK_RUN_LIVE=1 to enable)")))

(fn make-client []
  (CodexSdk.Codex {:codex-path (os.getenv "CODEX_PATH")}))

(fn live-run-and-resume []
  (if (should-skip?)
      (print-skip "codex-sdk live run and resume")
      (do
        (local client (make-client))
        (local thread (client:start-thread {:working-directory (fs.absolute ".")}))
        (local first (thread:run "Reply with exactly LIVE-CODEX-SDK-ONE and do not use tools."))
        (assert (not (= nil (string.find first.final-response "LIVE-CODEX-SDK-ONE" 1 true))))
        (assert thread.id "thread id should be populated after first live run")
        (local resumed (client:resume-thread thread.id {:working-directory (fs.absolute ".")}))
        (local second (resumed:run "Reply with exactly LIVE-CODEX-SDK-TWO and do not use tools."))
        (assert (not (= nil (string.find second.final-response "LIVE-CODEX-SDK-TWO" 1 true)))))))

(fn live-structured-output []
  (if (should-skip?)
      (print-skip "codex-sdk live structured output")
      (do
        (local client (make-client))
        (local thread (client:start-thread {:working-directory (fs.absolute ".")}))
        (local result
          (thread:run
            "Return JSON that matches the schema."
            {:output-schema {:type "object"
                             :properties {:status {:type "string"}
                                          :token {:type "string"}}
                             :required ["status" "token"]
                             :additionalProperties false}}))
        (local parsed (json.loads result.final-response))
        (assert (= parsed.status "ok"))
        (assert (= (type parsed.token) :string))
        (assert (> (# parsed.token) 0)))))

(fn live-streamed-events []
  (if (should-skip?)
      (print-skip "codex-sdk live streamed events")
      (do
        (local client (make-client))
        (local thread (client:start-thread {:working-directory (fs.absolute ".")}))
        (local event-types [])
        (var completed nil)
        (local handle
          (thread:run-streamed
            "Reply with exactly LIVE-CODEX-SDK-STREAM and do not use tools."
            {:on-event (fn [event]
                         (table.insert event-types event.type))
             :on-complete (fn [result]
                            (set completed result))}))
        (local ok
          (callbacks.run-loop {:poll-jobs false
                               :poll-http false
                               :poll-process false
                               :sleep-ms 1
                               :timeout-ms 120000
                               :until (fn []
                                        (handle:poll)
                                        completed)}))
        (assert ok "live streamed run should complete")
        (assert (>= (length event-types) 3))
        (assert (= (. event-types 1) :thread-started))
        (assert (= (. event-types 2) :turn-started))
        (assert completed)
        (assert (not (= nil (string.find completed.final-response "LIVE-CODEX-SDK-STREAM" 1 true)))))))

(fn live-image-input []
  (if (should-skip?)
      (print-skip "codex-sdk live image input")
      (do
        (local client (make-client))
        (local thread (client:start-thread {:working-directory (fs.absolute ".")}))
        (local image-path (app.engine.get-asset-path "pics/test.png"))
        (local result
          (thread:run
            [{:type :text :text "Return JSON matching the schema. Set has_image to true."}
             {:type :local-image :path image-path}]
            {:output-schema {:type "object"
                             :properties {:has_image {:type "boolean"}
                                          :note {:type "string"}}
                             :required ["has_image" "note"]
                             :additionalProperties false}}))
        (local parsed (json.loads result.final-response))
        (assert (= parsed.has_image true))
        (assert (= (type parsed.note) :string))
        (assert (> (# parsed.note) 0)))))

(fn live-skip-git-repo-check []
  (if (should-skip?)
      (print-skip "codex-sdk live skip git repo check")
      (do
        (local tempdir (tempfile.TemporaryDirectory {:prefix "codex-sdk-live-"}))
        (local dir tempdir.path)
        (local client (make-client))
        (local thread (client:start-thread {:working-directory dir
                                            :skip-git-repo-check true}))
        (local result (thread:run "Reply with exactly LIVE-CODEX-SDK-NOGIT and do not use tools."))
        (assert (not (= nil (string.find result.final-response "LIVE-CODEX-SDK-NOGIT" 1 true))))
        (tempdir:drop))))

(fn live-additional-directories []
  (if (should-skip?)
      (print-skip "codex-sdk live additional directories")
      (do
        (local extra (tempfile.TemporaryDirectory {:prefix "codex-sdk-extra-"}))
        (local file-path (fs.join-path extra.path "secret.txt"))
        (local marker "LIVE-CODEX-SDK-EXTRA-DIR")
        (fs.write-file file-path marker)
        (local client (make-client))
        (local thread (client:start-thread {:working-directory (fs.absolute ".")
                                            :additional-directories [extra.path]}))
        (local result
          (thread:run
            (.. "Read the file at " file-path " and reply with exactly its full contents. Do not add anything else.")))
        (assert (not (= nil (string.find result.final-response marker 1 true))))
        (extra:drop))))

(table.insert tests {:name "codex-sdk live run and resume" :fn live-run-and-resume})
(table.insert tests {:name "codex-sdk live structured output" :fn live-structured-output})
(table.insert tests {:name "codex-sdk live streamed events" :fn live-streamed-events})
(table.insert tests {:name "codex-sdk live image input" :fn live-image-input})
(table.insert tests {:name "codex-sdk live skip git repo check" :fn live-skip-git-repo-check})
(table.insert tests {:name "codex-sdk live additional directories" :fn live-additional-directories})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "codex-sdk-live"
                       :tests tests})))

{:name "codex-sdk-live"
 :tests tests
 :main main}

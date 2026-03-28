(local process (require :process))

(local internal-originator-env "CODEX_INTERNAL_ORIGINATOR_OVERRIDE")
(local default-originator "codex_sdk_fennel")

(fn executable-path [codex-path]
  (if codex-path codex-path "codex"))

(fn copy-env [source]
  (local env {})
  (each [k v (pairs (or source {}))]
    (tset env k v))
  env)

(fn build-env [options]
  (local env (copy-env options.env))
  (when (and (not options.originator) (= (. env internal-originator-env) nil))
    (tset env internal-originator-env default-originator))
  (when options.originator
    (tset env internal-originator-env options.originator))
  (when options.base-url
    (tset env :OPENAI_BASE_URL options.base-url))
  (when options.api-key
    (tset env :CODEX_API_KEY options.api-key))
  env)

(fn add-config-option! [args key value quoted?]
  (when (not (= value nil))
    (table.insert args "--config")
    (table.insert args (if quoted?
                           (.. key "=\"" value "\"")
                           (.. key "=" (tostring value))))))

(fn build-command-args [client options]
  (local args [client.codex-path "exec" "--experimental-json"])
  (when options.model
    (table.insert args "--model")
    (table.insert args options.model))
  (when options.sandbox-mode
    (table.insert args "--sandbox")
    (table.insert args options.sandbox-mode))
  (when options.working-directory
    (table.insert args "--cd")
    (table.insert args options.working-directory))
  (each [_ dir (ipairs (or options.additional-directories []))]
    (table.insert args "--add-dir")
    (table.insert args dir))
  (when options.skip-git-repo-check
    (table.insert args "--skip-git-repo-check"))
  (when options.output-schema-file
    (table.insert args "--output-schema")
    (table.insert args options.output-schema-file))
  (add-config-option! args "model_reasoning_effort" options.model-reasoning-effort true)
  (when (not (= options.network-access-enabled nil))
    (add-config-option! args "sandbox_workspace_write.network_access" options.network-access-enabled false))
  (if options.web-search-mode
      (add-config-option! args "web_search" options.web-search-mode true)
      (= options.web-search-enabled true)
      (add-config-option! args "web_search" "live" true)
      (= options.web-search-enabled false)
      (add-config-option! args "web_search" "disabled" true))
  (add-config-option! args "approval_policy" options.approval-policy true)
  (each [_ image (ipairs (or options.images []))]
    (table.insert args "--image")
    (table.insert args image))
  (when options.thread-id
    (table.insert args "resume")
    (table.insert args options.thread-id))
  args)

(fn ensure-process-success! [result]
  (when (or (not (= result.exit-code 0))
            result.signal)
    (local detail (if result.signal
                      (.. "signal " (tostring result.signal))
                      (.. "code " (tostring result.exit-code))))
    (error (.. "Codex Exec exited with " detail ": " (or result.stderr "")))))

(fn run [client options]
  (local result
    (process.run {:args (build-command-args client options)
                  :cwd options.working-directory
                  :env (build-env client)
                  :clear-env client.clear-env
                  :stdin options.input}))
  result)

(fn spawn [client options]
  (local id
    (process.spawn {:args (build-command-args client options)
                    :cwd options.working-directory
                    :env (build-env client)
                    :clear-env client.clear-env}))
  (when (> (# options.input) 0)
    (process.write id options.input))
  (process.close-stdin id)
  id)

(fn CodexExec [options]
  {:codex-path (executable-path options.codex-path)
   :base-url options.base-url
   :api-key options.api-key
   :env options.env
   :clear-env (if (= options.clear-env nil) false options.clear-env)
   :originator options.originator
   :run run
   :spawn spawn})

{:CodexExec CodexExec
 :build-command-args build-command-args
 :build-env build-env
 :ensure-process-success! ensure-process-success!}

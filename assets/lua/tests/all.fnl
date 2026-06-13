(fn concat-modules [left right]
  (local merged [])
  (each [_ item (ipairs left)]
    (table.insert merged item))
  (each [_ item (ipairs right)]
    (table.insert merged item))
  merged)

;; All Lua modules that can safely run in a single process.
;; Slow tests (C-IR, GCCJIT, hot-reload integration) must run separately
;; because their full-app bootstrap conflicts with prior suite state.
;; Use `make test-all-lua` to run fast+integration+slow in sequence.
(local fast-suite (require :tests/fast))
(local integration-suite (require :tests/integration))

(local suite
  {:name "all"
   :modules (concat-modules fast-suite.modules integration-suite.modules)})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-modules suite)))

{:name "all"
 :modules suite.modules
 :main main}

(fn concat-modules [left right]
  (local merged [])
  (each [_ item (ipairs left)]
    (table.insert merged item))
  (each [_ item (ipairs right)]
    (table.insert merged item))
  merged)

(local fast-suite (require :tests/fast))
(local slow-suite (require :tests/slow))

(local suite
  {:name "all"
   :modules (concat-modules fast-suite.modules slow-suite.modules)})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-modules suite)))

{:name "all"
 :modules suite.modules
 :main main}

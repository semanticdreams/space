(local tests [])

(fn next-frame-defers []
  (require :main)
  (local calls [])
  (app.next-frame
    (fn []
      (table.insert calls "first")
      (app.next-frame (fn [] (table.insert calls "second")))))
  (app.update 0)
  (assert (= (length calls) 1))
  (assert (= (. calls 1) "first"))
  (app.update 0)
  (assert (= (length calls) 2))
  (assert (= (. calls 2) "second"))
  true)

(fn next-frame-paused-by-ui-mode []
  (require :main)
  (local calls [])
  (local prev-settings app.settings)
  (local prev-state app.runtime-performance-state)
  (set app.settings nil)
  (set app.runtime-performance-state nil)
  (set app.runtime-performance-ui-paused true)
  (app.next-frame (fn [] (table.insert calls "ran")))
  (app.update 0)
  (assert (= (length calls) 0))
  (set app.runtime-performance-ui-paused false)
  (app.update 0)
  (set app.settings prev-settings)
  (set app.runtime-performance-state prev-state)
  (assert (= (length calls) 1))
  (assert (= (. calls 1) "ran"))
  true)

(table.insert tests {:name "next frame defers callbacks" :fn next-frame-defers})
(table.insert tests {:name "next frame waits while ui paused" :fn next-frame-paused-by-ui-mode})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-frame"
                       :tests tests})))

{:name "next-frame"
 :tests tests
 :main main}

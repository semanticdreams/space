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

(table.insert tests {:name "next frame defers callbacks" :fn next-frame-defers})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-frame"
                       :tests tests})))

{:name "next-frame"
 :tests tests
 :main main}

(local tests [])
(local Signal (require :signal))
(local debug debug)

(fn callbacks-upvalue [signal]
  (assert debug "Signal tests require debug library")
  (var callbacks nil)
  (for [idx 1 8]
    (when (not callbacks)
      (local (_name value) (debug.getupvalue signal.emit idx))
      (when (and (= (type value) :table)
                 (not (= value _G)))
        (set callbacks value))))
  (assert callbacks "Failed to locate Signal callbacks upvalue")
  callbacks)

(fn signal-emits-in-connection-order []
  (local signal (Signal))
  (local seen [])
  (signal:connect (fn [value]
                    (table.insert seen (.. "a:" value))))
  (signal:connect (fn [value]
                    (table.insert seen (.. "b:" value))))
  (signal:emit "x")
  (assert (= (length seen) 2))
  (assert (= (. seen 1) "a:x"))
  (assert (= (. seen 2) "b:x")))

(fn signal-disconnect-removes-only-first-duplicate-handler []
  (local signal (Signal))
  (var calls 0)
  (local handler (fn [_value]
                   (set calls (+ calls 1))))
  (signal:connect handler)
  (signal:connect handler)
  (signal:disconnect handler)
  (signal:emit "x")
  (assert (= calls 1)
          "Signal.disconnect should remove only the first matching handler"))

(fn signal-self-disconnect-only-affects-future-emits []
  (local signal (Signal))
  (var calls 0)
  (var handler nil)
  (set handler
       (signal:connect
         (fn [_value]
           (set calls (+ calls 1))
           (signal:disconnect handler true))))
  (signal:emit "x")
  (signal:emit "y")
  (assert (= calls 1)
          "Self-disconnected handler should not run again on later emits"))

(fn signal-disconnect-during-emit-skips-later-listener []
  (local signal (Signal))
  (local seen [])
  (var late-handler nil)
  (signal:connect
    (fn [_value]
      (table.insert seen "first")
      (signal:disconnect late-handler true)))
  (set late-handler
       (signal:connect
         (fn [_value]
           (table.insert seen "late"))))
  (signal:connect
    (fn [_value]
      (table.insert seen "last")))
  (signal:emit "x")
  (assert (= (length seen) 2))
  (assert (= (. seen 1) "first"))
  (assert (= (. seen 2) "last"))
  (signal:emit "y")
  (assert (= (length seen) 4))
  (assert (= (. seen 3) "first"))
  (assert (= (. seen 4) "last")))

(fn signal-clear-during-emit-stops-remaining-listeners []
  (local signal (Signal))
  (local seen [])
  (signal:connect
    (fn [_value]
      (table.insert seen "first")
      (signal:clear)))
  (signal:connect
    (fn [_value]
      (table.insert seen "second")))
  (signal:emit "x")
  (signal:emit "y")
  (assert (= (length seen) 1)
          "Signal.clear during emit should stop remaining listeners and future emits")
  (assert (= (. seen 1) "first")))

(fn signal-connect-during-emit-only-affects-future-emits []
  (local signal (Signal))
  (local seen [])
  (var late-calls 0)
  (signal:connect
    (fn [_value]
      (table.insert seen "first")
      (signal:connect
        (fn [_next]
          (set late-calls (+ late-calls 1))))))
  (signal:emit "x")
  (assert (= late-calls 0)
          "Listeners connected during emit should not run in the current emit")
  (signal:emit "y")
  (assert (= late-calls 1)
          "Listeners connected during emit should run on the next emit"))

(fn signal-nested-emit-sees-updated-active-listeners []
  (local signal (Signal))
  (local seen [])
  (var nested? false)
  (var late-handler nil)
  (signal:connect
    (fn [_value]
      (table.insert seen "first")
      (when (not nested?)
        (set nested? true)
        (signal:disconnect late-handler true)
        (signal:emit "nested"))))
  (set late-handler
       (signal:connect
         (fn [_value]
           (table.insert seen "late"))))
  (signal:emit "outer")
  (assert (= (length seen) 2))
  (assert (= (. seen 1) "first"))
  (assert (= (. seen 2) "first")))

(fn signal-disconnect-missing-still-errors-by-default []
  (local signal (Signal))
  (local (ok err)
    (pcall (fn []
             (signal:disconnect (fn [] nil)))))
  (assert (not ok))
  (assert (string.find (tostring err) "Signal handler not connected" 1 true)))

(fn signal-erroring-emit-still-unwinds-compaction []
  (local signal (Signal))
  (local broken-handler
    (signal:connect
      (fn [_value]
        (error "signal test failure"))))
  (local later-handler
    (signal:connect
      (fn [_value] nil)))
  (assert (= (length (callbacks-upvalue signal)) 2))
  (local (ok err)
    (pcall (fn []
             (signal:emit "x"))))
  (assert (not ok))
  (assert (string.find (tostring err) "signal test failure" 1 true))
  (signal:disconnect later-handler true)
  (assert (= (length (callbacks-upvalue signal)) 1)
          "Signal should compact callback storage after a failing emit unwinds")
  (signal:disconnect broken-handler true)
  (assert (= (length (callbacks-upvalue signal)) 0)
          "Signal should continue compacting after later disconnects"))

(table.insert tests {:name "Signal emits in connection order"
                     :fn signal-emits-in-connection-order})
(table.insert tests {:name "Signal disconnect removes only first duplicate handler"
                     :fn signal-disconnect-removes-only-first-duplicate-handler})
(table.insert tests {:name "Signal self-disconnect only affects future emits"
                     :fn signal-self-disconnect-only-affects-future-emits})
(table.insert tests {:name "Signal disconnect during emit skips later listener"
                     :fn signal-disconnect-during-emit-skips-later-listener})
(table.insert tests {:name "Signal clear during emit stops remaining listeners"
                     :fn signal-clear-during-emit-stops-remaining-listeners})
(table.insert tests {:name "Signal connect during emit only affects future emits"
                     :fn signal-connect-during-emit-only-affects-future-emits})
(table.insert tests {:name "Signal nested emit sees updated active listeners"
                     :fn signal-nested-emit-sees-updated-active-listeners})
(table.insert tests {:name "Signal disconnect missing still errors by default"
                     :fn signal-disconnect-missing-still-errors-by-default})
(table.insert tests {:name "Signal erroring emit still unwinds compaction"
                     :fn signal-erroring-emit-still-unwinds-compaction})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "signal"
                       :tests tests})))

{:name "signal"
 :main main}

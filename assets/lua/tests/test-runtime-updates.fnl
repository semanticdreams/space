(local tests [])
(local RuntimeUpdates (require :runtime-updates))

(fn reset-updates []
  (RuntimeUpdates.clear)
  (set app.__runtime_updates nil))

(fn runtime-frame-subscription-receives-delta-and-disconnects-cleanly []
  (reset-updates)
  (local deltas [])
  (local subscription
    (RuntimeUpdates.FrameSubscription {:callback (fn [delta]
                                                   (table.insert deltas delta))}))
  (subscription:start)
  (app.engine.events.updated:emit 16)
  (app.engine.events.updated:emit 32)
  (assert (= (length deltas) 2) "Frame subscription should receive each frame")
  (assert (= (. deltas 1) 16))
  (assert (= (. deltas 2) 32))
  (assert app.__runtime_updates.update-handler
          "Frame subscription should keep the shared update handler active while running")
  (subscription:drop)
  (assert (= app.__runtime_updates.update-handler nil)
          "Dropping the last frame subscription should disconnect the shared handler"))

(fn runtime-frame-subscription-can-cancel-itself []
  (reset-updates)
  (var calls 0)
  (var subscription nil)
  (set subscription
       (RuntimeUpdates.FrameSubscription {:callback (fn [_delta]
                                                      (set calls (+ calls 1))
                                                      (subscription:drop))}))
  (subscription:start)
  (app.engine.events.updated:emit 16)
  (app.engine.events.updated:emit 16)
  (assert (= calls 1) "Self-dropping frame subscription should stop future frames")
  (assert (= app.__runtime_updates.update-handler nil)
          "Self-dropping frame subscription should disconnect the shared handler"))

(fn runtime-frame-subscription-clear-stops-siblings-in-same-tick []
  (reset-updates)
  (local calls [])
  (local first
    (RuntimeUpdates.FrameSubscription {:callback (fn [_delta]
                                                   (table.insert calls "first")
                                                   (RuntimeUpdates.clear))}))
  (local second
    (RuntimeUpdates.FrameSubscription {:callback (fn [_delta]
                                                    (table.insert calls "second"))}))
  (first:start)
  (second:start)
  (app.engine.events.updated:emit 16)
  (assert (= (length calls) 1)
          "Clearing from a frame callback should stop sibling callbacks in the same tick")
  (assert (= (. calls 1) "first"))
  (assert (= app.__runtime_updates.update-handler nil)
          "Clearing frame subscriptions should disconnect the shared handler"))

(table.insert tests {:name "RuntimeUpdates frame subscription receives delta"
                     :fn runtime-frame-subscription-receives-delta-and-disconnects-cleanly})
(table.insert tests {:name "RuntimeUpdates frame subscription can cancel itself"
                     :fn runtime-frame-subscription-can-cancel-itself})
(table.insert tests {:name "RuntimeUpdates clear stops sibling frame callbacks"
                     :fn runtime-frame-subscription-clear-stops-siblings-in-same-tick})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "runtime-updates"
                       :tests tests})))

{:main main}

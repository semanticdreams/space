(local tests [])
(local TouchRouter (require :touch-router))

(fn touch-payload [finger-id x y timestamp]
  (local payload {:x x
                  :y y
                  :xrel 0
                  :yrel 0
                  :pressure 1.0
                  :timestamp timestamp})
  (tset payload "touch-id" 1)
  (tset payload "finger-id" finger-id)
  payload)

(fn touch-router-notifies-candidate-before-capture []
  (local events [])
  (local target
    {:on-touch-drag-candidate-start
     (fn [_self payload]
       (table.insert events (.. "candidate-start:" payload.start-y)))
     :on-touch-drag-start
     (fn [_self payload]
       (table.insert events (.. "drag-start:" payload.start-y))
       true)
     :on-touch-drag
     (fn [_self payload]
       (table.insert events (.. "drag:" payload.y))
       true)
     :on-touch-drag-end
     (fn [_self payload]
       (table.insert events (.. "drag-end:" payload.y))
       true)})
  (local router
    (TouchRouter {:drag-threshold 2
                  :select-drag-candidate (fn [_ctx _payload _session]
                                           target)}))
  (assert (router:on-touch-down {} (touch-payload 2 1 10 100)))
  (assert (router:on-touch-motion {} (touch-payload 2 1 13 116)))
  (assert (router:on-touch-up {} (touch-payload 2 1 13 117)))
  (assert (= (. events 1) "candidate-start:10"))
  (assert (= (. events 2) "drag-start:10"))
  (assert (= (. events 3) "drag:13"))
  (assert (= (. events 4) "drag-end:13")))

(fn touch-router-cancels-candidate-before-capture []
  (local events [])
  (local target
    {:on-touch-drag-candidate-start
     (fn [_self payload]
       (table.insert events (.. "candidate-start:" payload.start-y)))
     :on-touch-drag-candidate-cancel
     (fn [_self payload]
       (table.insert events (.. "candidate-cancel:" payload.start-y)))})
  (local router
    (TouchRouter {:drag-threshold 20
                  :select-drag-candidate (fn [_ctx _payload _session]
                                           target)}))
  (assert (router:on-touch-down {} (touch-payload 2 1 10 100)))
  (assert (router:on-touch-canceled {} (touch-payload 2 1 11 116)))
  (assert (= (. events 1) "candidate-start:10"))
  (assert (= (. events 2) "candidate-cancel:10")))

(fn touch-router-uses-target-specific-drag-threshold []
  (local events [])
  (local target
    {:touch-drag-threshold 3
     :on-touch-drag-candidate-start
     (fn [_self _payload]
       (table.insert events "candidate-start")
       true)
     :on-touch-drag-start
     (fn [_self _payload]
       (table.insert events "drag-start")
       true)
     :on-touch-drag
     (fn [_self payload]
       (table.insert events (.. "drag:" payload.y))
       true)
     :on-touch-drag-end
     (fn [_self payload]
       (table.insert events (.. "drag-end:" payload.y))
       true)})
  (local router
    (TouchRouter {:drag-threshold 20
                  :select-drag-candidate (fn [_ctx _payload _session]
                                           target)}))
  (assert (router:on-touch-down {} (touch-payload 2 1 10 100)))
  (assert (not (router:on-touch-motion {} (touch-payload 2 1 12 116))))
  (assert (router:on-touch-motion {} (touch-payload 2 1 13 132)))
  (assert (router:on-touch-up {} (touch-payload 2 1 13 140)))
  (assert (= (length events) 4))
  (assert (= (. events 1) "candidate-start"))
  (assert (= (. events 2) "drag-start"))
  (assert (= (. events 3) "drag:13"))
  (assert (= (. events 4) "drag-end:13")))

(table.insert tests {:name "TouchRouter notifies candidate before capture"
                     :fn touch-router-notifies-candidate-before-capture})
(table.insert tests {:name "TouchRouter cancels candidate before capture"
                     :fn touch-router-cancels-candidate-before-capture})
(table.insert tests {:name "TouchRouter uses target-specific drag threshold"
                     :fn touch-router-uses-target-specific-drag-threshold})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "touch-router"
                       :tests tests})))

{:name "touch-router"
 :tests tests
 :main main}

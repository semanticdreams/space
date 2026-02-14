(local _ (require :main))
(local NextLayout (require :next-app/layout))
(local Router (require :next-app/interaction-router))

(local tests [])

(fn make-node [x y w h z]
  (local node (NextLayout.Node.new {:name "node"}))
  (node:set-frame x y z w h 0 0 {:mark-dirty? false})
  (node:transform-pass nil)
  node)

(fn next-router-dispatches-click-to-topmost-hit []
  (local router (Router.new))
  (local low (make-node 0 0 1 1 0))
  (local high (make-node 0 0 1 1 0.5))
  (var low-clicked 0)
  (var high-clicked 0)
  (set low.on-click (fn [_self _event] (set low-clicked (+ low-clicked 1))))
  (set high.on-click (fn [_self _event] (set high-clicked (+ high-clicked 1))))
  (router:register-clickable low)
  (router:register-clickable high)
  (router:dispatch-click 0.4 0.4 {:button 1})
  (assert (= low-clicked 0))
  (assert (= high-clicked 1)))

(fn next-router-dispatches-hover-enter-leave []
  (local router (Router.new))
  (local node (make-node 0 0 1 1 0))
  (var enters 0)
  (var leaves 0)
  (set node.on-hovered
       (fn [_self hovered?]
         (if hovered?
             (set enters (+ enters 1))
             (set leaves (+ leaves 1)))))
  (router:register-hoverable node)
  (router:dispatch-hover 0.2 0.2)
  (router:dispatch-hover 2 2)
  (assert (= enters 1))
  (assert (= leaves 1)))

(table.insert tests {:name "Next interaction router click picks topmost"
                     :fn next-router-dispatches-click-to-topmost-hit})
(table.insert tests {:name "Next interaction router hover emits enter/leave"
                     :fn next-router-dispatches-hover-enter-leave})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-app-interaction-router"
                       :tests tests})))

{:name "next-app-interaction-router"
 :tests tests
 :main main}

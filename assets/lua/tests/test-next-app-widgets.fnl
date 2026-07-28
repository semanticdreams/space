(local NextLayout (require :next-app/layout))
(local PanelWidget (require :next-app/panel-widget))
(local ButtonWidget (require :next-app/button-widget))

(local tests [])

(fn approx [a b]
  (< (math.abs (- a b)) 1e-5))

(fn fixed-node [w h]
  (NextLayout.Node.new
    {:name "fixed"
     :measure-fn (fn [self _mw _mh _md]
                   (self:set-measure w h 0))
     :layout-fn (fn [self width height depth]
                  (self:set-size width height depth {:mark-dirty? false}))}))

(fn next-panel-measures-child-and-padding []
  (local child (fixed-node 0.6 0.2))
  (local panel
    (PanelWidget {:name "panel-under-test"
                  :padding [0.1 0.05]
                  :child child}))
  (NextLayout.run-frame panel 1.2 0.6 0)
  (assert (approx panel.measured-width 0.8))
  (assert (approx panel.measured-height 0.3))
  (assert (approx child.width 1.0))
  (assert (approx child.height 0.5))
  (assert (approx child.local-x 0.1))
  (assert (approx child.local-y 0.05))

  (var captured nil)
  (local batcher {:add-quad (fn [_self payload]
                              (set captured payload))})
  (panel:emit-quads batcher)
  (assert captured "panel should emit quad payload")
  (assert captured.matrix "panel quad payload should include matrix")
  (assert captured.color "panel quad payload should include color"))

(fn next-button-measures-label-and-emits-quad []
  (local button
    (ButtonWidget {:name "button-under-test"
                   :text "Launch"
                   :clickables {:register (fn [_ _] nil) :unregister (fn [_ _] nil)}
                   :hoverables {:register (fn [_ _] nil) :unregister (fn [_ _] nil)}}))
  (NextLayout.run-frame button 1.2 0.4 0)
  (assert (> button.measured-width 0))
  (assert (> button.measured-height 0))
  (assert (approx button.label.local-x (/ (- button.width button.label.width) 2)))
  (assert (approx button.label.local-y (/ (- button.height button.label.height) 2)))

  (var captured nil)
  (local batcher {:add-quad (fn [_self payload]
                              (set captured payload))})
  (button:emit-quads batcher)
  (assert captured "button should emit quad payload")
  (assert captured.matrix "button quad payload should include matrix")
  (assert captured.color "button quad payload should include color"))

(table.insert tests {:name "Next panel measures child and padding"
                     :fn next-panel-measures-child-and-padding})
(table.insert tests {:name "Next button measures label and emits quad"
                     :fn next-button-measures-label-and-emits-quad})

;; A4-1: adapter arity — prove adapter methods forward widget nodes to router
(fn build-ui-root-registers-widgets-with-router []
  "Prove that adapter methods with _self+node arity forward the correct
  widget node to the router, not the adapter table itself."
  (local InteractionRouter (require :next-app/interaction-router))
  (local router (InteractionRouter.new))
  ;; Same adapter pattern as build-ui-root
  (local clickables
    {:register (fn [_self node] (router:register-clickable node))
     :unregister (fn [_self node] (router:unregister-clickable node))
     :register-right-click (fn [_self node] (router:register-clickable node))
     :unregister-right-click (fn [_self node] (router:unregister-clickable node))
     :register-double-click (fn [_self node] (router:register-clickable node))
     :unregister-double-click (fn [_self node] (router:unregister-clickable node))})
  (local hoverables
    {:register (fn [_self node] (router:register-hoverable node))
     :unregister (fn [_self node] (router:unregister-hoverable node))})
  ;; Simulate widget method-call arity: (clickables:register node)
  ;; passes clickables as self, node as first explicit arg
  (local fake-button {:name "button-node"})
  (local fake-toggle {:name "toggle-node"})
  (clickables:register fake-button)
  (clickables:register-right-click fake-toggle)
  (hoverables:register fake-button)
  (hoverables:register fake-toggle)
  ;; Router arrays should contain the actual nodes, not adapters
  (assert (= (length router.clickables) 2)
          "router.clickables should have 2 registered nodes")
  (assert (= (. router.clickables 1) fake-button)
          "first clickable should be fake-button")
  (assert (= (. router.clickables 2) fake-toggle)
          "second clickable should be fake-toggle")
  (assert (= (length router.hoverables) 2)
          "router.hoverables should have 2 registered nodes")
  (assert (= (. router.hoverables 1) fake-button)
          "first hoverable should be fake-button")
  (assert (= (. router.hoverables 2) fake-toggle)
          "second hoverable should be fake-toggle")
  ;; Unregister works too
  (clickables:unregister fake-button)
  (hoverables:unregister fake-toggle)
  (assert (= (length router.clickables) 1)
          "router.clickables should have 1 after unregister")
  (assert (= (length router.hoverables) 1)
          "router.hoverables should have 1 after unregister"))
(table.insert tests {:name "build-ui-root registers widgets with router via adapters"
                     :fn build-ui-root-registers-widgets-with-router})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-app-widgets"
                       :tests tests})))

{:name "next-app-widgets"
 :tests tests
 :main main}

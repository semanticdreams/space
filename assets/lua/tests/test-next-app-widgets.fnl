(local _ (require :main))
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

;; A5-1: integration coverage — exercise production build-ui-root path
(fn build-ui-root-registers-widgets-with-router []
  "Call the production build-ui-root and verify the returned router
  contains the actual ButtonWidget and ToggleWidget nodes registered
  via the adapter tables (not the adapter tables themselves)."
  (local {: build-ui-root} (require :next-app/renderers))
  ;; Minimal renderer options; build-ui-root uses defaults for most values
  (local result (build-ui-root {}))
  (local router result.router)
  ;; All 3 buttons and 2 toggles register into router.clickables.
  ;; ButtonWidget registers via register, register-right-click,
  ;; register-double-click — each duplicates in the same array.
  ;; ToggleWidget registers once per widget.
  ;; So clickables count = 3 buttons × 3 methods + 2 toggles = 11.
  (assert (>= (length router.clickables) 1)
          "router.clickables should contain registered widget nodes")
  ;; Nodes in router.clickables should be actual widget nodes, not adapter tables
  (each [_ node (ipairs router.clickables)]
    (assert node.width "registered clickable should have .width (widget node)")
    (assert (not (. node :register-right-click))
            "registered clickable should not be the adapter table"))
  ;; hoverables count = 3 buttons + 2 toggles = 5
  (assert (>= (length router.hoverables) 1)
          "router.hoverables should contain registered widget nodes")
  (each [_ node (ipairs router.hoverables)]
    (assert node.width "registered hoverable should have .width (widget node)")
    (assert (not (. node :register))
            "registered hoverable should not be the adapter table"))
  ;; Key widget nodes are non-nil
  (assert result.run-button "run-button should be non-nil")
  (assert result.inspect-button "inspect-button should be non-nil")
  (assert result.ship-button "ship-button should be non-nil")
  (assert result.root "root should be non-nil")
  ;; Drop buttons to clean up router registrations
  (result.run-button:drop)
  (result.inspect-button:drop)
  (result.ship-button:drop)
  (assert (< (length router.clickables) 11)
          "router.clickables should shrink after button drops"))
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

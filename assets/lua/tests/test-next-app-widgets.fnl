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

;; A7-1: occurrence-count helper + per-widget exact-count assertions
(fn count-occurrences [arr name]
  "Return how many nodes in arr have .name == name."
  (var n 0)
  (each [_ node (ipairs arr)]
    (when (= (. node :name) name)
      (set n (+ n 1))))
  n)

(fn build-ui-root-registers-widgets-with-router []
  "Call the production build-ui-root and assert exact per-widget
  registration counts in router.clickables/hoverables."
  (local {: build-ui-root} (require :next-app/renderers))
  (local result (build-ui-root {}))
  (local router result.router)

  ;; ---- per-widget clickables counts ----
  ;; Buttons: register + register-right-click + register-double-click = 3 each
  (local button-names ["next-button-run" "next-button-inspect" "next-button-ship"])
  (each [_ name (ipairs button-names)]
    (assert (= (count-occurrences router.clickables name) 3)
            (.. name " should appear 3× in router.clickables, got "
                (count-occurrences router.clickables name))))
  ;; Toggles: register once = 1 each
  (local toggle-names ["next-toggle-perf" "next-toggle-logs"])
  (each [_ name (ipairs toggle-names)]
    (assert (= (count-occurrences router.clickables name) 1)
            (.. name " should appear 1× in router.clickables, got "
                (count-occurrences router.clickables name))))

  ;; ---- per-widget hoverables counts (all appear once) ----
  (each [_ name (ipairs button-names)]
    (assert (= (count-occurrences router.hoverables name) 1)
            (.. name " should appear 1× in router.hoverables, got "
                (count-occurrences router.hoverables name))))
  (each [_ name (ipairs toggle-names)]
    (assert (= (count-occurrences router.hoverables name) 1)
            (.. name " should appear 1× in router.hoverables, got "
                (count-occurrences router.hoverables name))))

  ;; ---- adapter sanity (no entry is the adapter table) ----
  (each [_ node (ipairs router.clickables)]
    (assert (not (. node :register-right-click))
            (.. "clickable " (tostring (. node :name)) " should not be adapter"))
    (assert node.width "clickable entry should be a widget node"))
  (each [_ node (ipairs router.hoverables)]
    (assert (not (. node :register))
            (.. "hoverable " (tostring (. node :name)) " should not be adapter"))
    (assert node.width "hoverable entry should be a widget node"))

  ;; ---- returned named nodes ----
  (assert result.run-button "run-button should be returned")
  (assert result.inspect-button "inspect-button should be returned")
  (assert result.ship-button "ship-button should be returned")
  (assert result.perf-toggle "perf-toggle should be returned")
  (assert result.logs-toggle "logs-toggle should be returned")
  (assert result.root "root should be returned")

  ;; ---- drop cleanup with per-widget counts ----
  (result.run-button:drop)
  (result.inspect-button:drop)
  (result.ship-button:drop)
  ;; After 3 button drops: only toggles remain
  (each [_ name (ipairs toggle-names)]
    (assert (= (count-occurrences router.clickables name) 1)
            (.. name " should still be 1× in clickables after button drops, got "
                (count-occurrences router.clickables name))))
  (each [_ name (ipairs button-names)]
    (assert (= (count-occurrences router.clickables name) 0)
            (.. name " should be 0× in clickables after drop, got "
                (count-occurrences router.clickables name))))
  (each [_ name (ipairs toggle-names)]
    (assert (= (count-occurrences router.hoverables name) 1)
            (.. name " should still be 1× in hoverables after button drops, got "
                (count-occurrences router.hoverables name))))

  ;; Drop toggles → all arrays empty
  (result.perf-toggle:drop)
  (result.logs-toggle:drop)
  (assert (= (length router.clickables) 0)
          "router.clickables should be empty after all drops")
  (assert (= (length router.hoverables) 0)
          "router.hoverables should be empty after all drops"))
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

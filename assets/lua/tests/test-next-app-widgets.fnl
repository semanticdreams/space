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

;; A6-1: precise integration coverage — exact registration counts and named nodes
(fn build-ui-root-registers-widgets-with-router []
  "Call the production build-ui-root and assert exact router registration
  counts and that every expected widget node (by name) appears in the
  appropriate router arrays."
  (local {: build-ui-root} (require :next-app/renderers))
  (local result (build-ui-root {}))
  (local router result.router)

  ;; ---- exact clickables registration ----
  ;; 3 buttons register × 3 methods each (register, register-right-click,
  ;; register-double-click) + 2 toggles × 1 = 11
  (assert (= (length router.clickables) 11)
          (.. "router.clickables should be 11, got " (length router.clickables)))

  ;; No entry is the adapter table (adapters have .register-right-click)
  (each [_ node (ipairs router.clickables)]
    (assert (not (. node :register-right-click))
            (.. "clickables entry should not be adapter: " (tostring (. node :name))))
    (assert node.width "clickables entry should be a widget node"))

  ;; All five named widgets appear in router.clickables
  (local widget-names ["next-button-run" "next-button-inspect" "next-button-ship"
                        "next-toggle-perf" "next-toggle-logs"])
  (each [_ expected-name (ipairs widget-names)]
    (var found false)
    (each [_ node (ipairs router.clickables)]
      (when (= (. node :name) expected-name)
        (set found true)))
    (assert found (.. expected-name " should be in router.clickables")))

  ;; ---- exact hoverables registration ----
  ;; 3 buttons + 2 toggles = 5
  (assert (= (length router.hoverables) 5)
          (.. "router.hoverables should be 5, got " (length router.hoverables)))

  (each [_ node (ipairs router.hoverables)]
    (assert (not (. node :register))
            (.. "hoverables entry should not be adapter: " (tostring (. node :name))))
    (assert node.width "hoverables entry should be a widget node"))

  (each [_ expected-name (ipairs widget-names)]
    (var found false)
    (each [_ node (ipairs router.hoverables)]
      (when (= (. node :name) expected-name)
        (set found true)))
    (assert found (.. expected-name " should be in router.hoverables")))

  ;; ---- returned named nodes ----
  (assert result.run-button "run-button should be returned")
  (assert result.inspect-button "inspect-button should be returned")
  (assert result.ship-button "ship-button should be returned")
  (assert result.perf-toggle "perf-toggle should be returned")
  (assert result.logs-toggle "logs-toggle should be returned")
  (assert result.root "root should be returned")

  ;; ---- drop cleanup ----
  ;; 3 buttons × 3 drop methods = 9 clickables removed; 2 toggles remain
  (result.run-button:drop)
  (result.inspect-button:drop)
  (result.ship-button:drop)
  (assert (= (length router.clickables) 2)
          (.. "router.clickables should be 2 after button drops, got "
              (length router.clickables)))
  ;; Remaining clickables are the toggles
  (each [_ expected-name (ipairs ["next-toggle-perf" "next-toggle-logs"])]
    (var found false)
    (each [_ node (ipairs router.clickables)]
      (when (= (. node :name) expected-name)
        (set found true)))
    (assert found (.. expected-name " should remain after button drops")))

  ;; hoverables: 3 buttons dropped → 2 toggles remain
  (assert (= (length router.hoverables) 2)
          (.. "router.hoverables should be 2 after button drops, got "
              (length router.hoverables)))
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

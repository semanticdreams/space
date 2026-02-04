(local Harness (require :tests.e2e.harness))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local {: FocusManager} (require :focus))

(fn run [ctx]
  (local states
    [{:label "Idle"}
     {:label "Hover" :hovered? true}
     {:label "Focused" :focused? true}
     {:label "Pressed" :pressed? true}
     {:label "Hover+Focus" :hovered? true :focused? true}
     {:label "Pressed+Focus" :pressed? true :focused? true}
     {:label "Hover+Press" :hovered? true :pressed? true}
     {:label "Hover+Press+Focus" :hovered? true :pressed? true :focused? true}])
  (local row-size 2)
  (local state-buttons [])

  (fn build-button [state]
    (fn [child-ctx]
      (local button ((Button {:text state.label
                              :variant :secondary
                              :padding [0.7 0.7]}) child-ctx))
      (table.insert state-buttons {:button button :state state})
      button))

  (fn make-row [row-states]
    (Flex {:axis :x
           :xspacing 0.8
           :yalign :center
           :children (icollect [_ state (ipairs row-states)]
                               (FlexChild (build-button state)))}))

  (local row-count (/ (length states) row-size))
  (local rows [])
  (for [row 1 row-count]
    (local start (+ 1 (* (- row 1) row-size)))
    (local row-states [])
    (for [i start (+ start (- row-size 1))]
      (table.insert row-states (. states i)))
    (table.insert rows (make-row row-states)))

  (local column-builder
    (Flex {:axis :y
           :yspacing 0.6
           :xalign :center
           :children (icollect [_ row-builder (ipairs rows)]
                               (FlexChild row-builder 0))}))

  (local focus-manager (FocusManager {:root-name "e2e-button-states"}))
  (local target
    (Harness.make-screen-target {:width ctx.width
                                 :height ctx.height
                                 :world-units-per-pixel ctx.units-per-pixel
                                 :focus-manager focus-manager
                                 :builder column-builder}))

  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (fn apply-focus-state [button focused?]
    ;; Snapshot wants multiple focused combos at once, so set focus state directly.
    (set button.focused? (not (not focused?)))
    (button:update-focus-visual {:mark-layout-dirty? false})
    (button:update-background-color {:mark-layout-dirty? false}))

  (each [_ entry (ipairs state-buttons)]
    (local button entry.button)
    (local state entry.state)
    (when (and state.hovered? (not (= state.hovered? nil)))
      (button:on-hovered state.hovered?))
    (when (and state.pressed? (not (= state.pressed? nil)))
      (button:on-pressed state.pressed?))
    (when (not (= state.focused? nil))
      (apply-focus-state button state.focused?)))

  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (Harness.capture-snapshot {:name "button-states"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target target))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E button-states snapshot complete"))

{:run run
 :main main}

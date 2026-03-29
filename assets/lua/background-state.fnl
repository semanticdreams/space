(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn default-state []
  {:color [0.0 0.0 0.0]})

(fn normalize-complete-state [state context]
  (local label (or context "BackgroundState"))
  (assert (= (type state) :table) (.. label " requires background state table"))
  (assert (= (type state.color) :table) (.. label " requires table :color"))
  (assert (= (length state.color) 3) (.. label " requires :color with 3 numbers"))
  (each [idx value (ipairs state.color)]
    (assert (= (type value) :number)
            (.. label " requires numeric :color[" (tostring idx) "]")))
  {:color [(. state.color 1) (. state.color 2) (. state.color 3)]})

(fn clear-components [state]
  (local normalized (normalize-complete-state state "BackgroundState.clear-components"))
  [(. normalized.color 1) (. normalized.color 2) (. normalized.color 3) 1.0])

{:default-state default-state
 :normalize-complete-state normalize-complete-state
 :clear-components clear-components
 :clone-state clone-table}

;; StatusBadge tests

(local glm (require :glm))
(local StatusBadge (require :status-badge))
(local {: Layout} (require :layout))
(local AppBootstrap (require :app-bootstrap))
(local BuildContext (require :build-context))

(local tests [])

(fn make-test-ctx []
  (AppBootstrap.init-themes)
  (BuildContext {}))

(fn test-requires-text []
  (local (ok err) (pcall (fn [] (StatusBadge {}) {})))
  (assert (not ok) "StatusBadge should require :text"))

(fn test-constructs-with-text []
  (local ctx (make-test-ctx))
  (local instance ((StatusBadge {:text "running" :tone :info}) ctx))
  (assert instance "should construct successfully")
  (assert instance.layout "should have a layout"))

(fn test-all-tones-construct []
  (local ctx (make-test-ctx))
  (local tones [:neutral :info :success :warning :danger])
  (each [_ tone (ipairs tones)]
    (local instance ((StatusBadge {:text tone :tone tone}) ctx))
    (assert instance (.. "should construct with tone " tone))))

(fn test-set-text []
  (local ctx (make-test-ctx))
  (local instance ((StatusBadge {:text "idle" :tone :neutral}) ctx))
  (instance:set-text "running")
  (assert true "set-text should not throw"))

(fn test-set-tone []
  (local ctx (make-test-ctx))
  (local instance ((StatusBadge {:text "idle" :tone :neutral}) ctx))
  (instance:set-tone :danger)
  (assert true "set-tone should not throw"))

(fn test-drop []
  (local ctx (make-test-ctx))
  (local instance ((StatusBadge {:text "test" :tone :neutral}) ctx))
  (instance:drop)
  (assert true "drop should not throw"))

(table.insert tests {:name "StatusBadge requires :text"
                     :fn test-requires-text})
(table.insert tests {:name "StatusBadge constructs with text"
                     :fn test-constructs-with-text})
(table.insert tests {:name "StatusBadge all tones construct"
                     :fn test-all-tones-construct})
(table.insert tests {:name "StatusBadge set-text works"
                     :fn test-set-text})
(table.insert tests {:name "StatusBadge set-tone works"
                     :fn test-set-tone})
(table.insert tests {:name "StatusBadge drop works"
                     :fn test-drop})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "status-badge"
                     :tests tests}))

{:tests tests
 :main main}

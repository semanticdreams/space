;; DisclosureRow tests

(local glm (require :glm))
(local DisclosureRow (require :disclosure-row))
(local {: Layout} (require :layout))
(local AppBootstrap (require :app-bootstrap))
(local BuildContext (require :build-context))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local Intersectables (require :intersectables))

(local tests [])

(fn make-icons-stub []
  (local font nil)
  (local codepoint-map {"expand_more" 0xE5CF
                        "chevron_right" 0xE5CC})
  (fn resolve [self name]
    (when name
      (local cp (. codepoint-map name))
      (when cp
        {:type :font
         :codepoint cp
         :font font})))
  {:resolve resolve})

(fn make-test-ctx []
  (AppBootstrap.init-themes)
  (local intersector (Intersectables))
  (local clickables (Clickables {:intersectables intersector}))
  (local hoverables (Hoverables {:intersectables intersector}))
  (BuildContext {:clickables clickables
                 :hoverables hoverables
                 :icons (make-icons-stub)}))

(fn make-instrumented-widget [name opts]
  (local options (or opts {}))
  (local measure (or options.measure (glm.vec3 5 2 0)))
  (var state {:builder-count 0
              :drop-count 0
              :measurer-count 0
              :layouter-count 0
              :dropped? false
              :received-size nil
              :received-position nil
              :received-rotation nil})
  (fn builder [_ctx]
    (set state.builder-count (+ state.builder-count 1))
    (local layout
      (Layout {:name (.. name "-layout")
               :measurer (fn [self]
                           (set state.measurer-count (+ state.measurer-count 1))
                           (set self.measure measure))
               :layouter (fn [self]
                           (set state.layouter-count (+ state.layouter-count 1))
                           (set state.received-size self.size)
                           (set state.received-position self.position)
                           (set state.received-rotation self.rotation))}))
    (fn drop [self]
      (set state.drop-count (+ state.drop-count 1))
      (set state.dropped? true)
      (self.layout:drop))
    {:layout layout
     :drop drop})
  (values builder state))

(fn test-requires-summary []
  (local (ok err) (pcall (fn [] (DisclosureRow {:details (fn [_ctx] {})}))))
  (assert (not ok) "should require :summary field"))

(fn test-constructs-successfully []
  (local ctx (make-test-ctx))
  (local (summary-builder _) (make-instrumented-widget "summary"))
  (local instance ((DisclosureRow {:summary summary-builder}) ctx))
  (assert (not (not instance)) "instance should be non-nil"))

(fn test-drop-cascades []
  (local ctx (make-test-ctx))
  (local (summary-builder summary-state) (make-instrumented-widget "summary"))
  (local (details-builder details-state) (make-instrumented-widget "details"))
  (local instance
    ((DisclosureRow {:summary summary-builder
                     :details details-builder
                     :expanded? true})
     ctx))
  (instance:drop)
  (assert summary-state.dropped? "summary should be dropped")
  (assert details-state.dropped? "details should be dropped"))

(fn test-expanded-state []
  (local ctx (make-test-ctx))
  (local (summary-builder _) (make-instrumented-widget "summary"))
  (local instance ((DisclosureRow {:summary summary-builder :expanded? false}) ctx))
  (assert (not (instance:expanded?)) "should start collapsed")
  (instance:set-expanded true)
  (assert (instance:expanded?) "should become expanded"))

(fn test-on-toggle-callback []
  (local ctx (make-test-ctx))
  (local (summary-builder _) (make-instrumented-widget "summary"))
  (var toggled nil)
  (local instance
    ((DisclosureRow {:summary summary-builder
                     :on-toggle (fn [val] (set toggled val))})
     ctx))
  (instance:set-expanded true)
  (assert toggled "toggle callback should fire with expanded=true"))

(fn test-measure-expanded-vs-collapsed []
  (local ctx (make-test-ctx))
  (local (summary-builder _) (make-instrumented-widget "summary" {:measure (glm.vec3 4 1 0)}))
  (local (details-builder _) (make-instrumented-widget "details" {:measure (glm.vec3 4 2 0)}))
  (local collapsed
    ((DisclosureRow {:summary summary-builder
                     :details details-builder
                     :expanded? false})
     ctx))
  (collapsed.layout:measurer)
  (local ch collapsed.layout.measure.y)
  (local expanded
    ((DisclosureRow {:summary summary-builder
                     :details details-builder
                     :expanded? true})
     ctx))
  (expanded.layout:measurer)
  (assert (> expanded.layout.measure.y ch)
          "expanded height should be greater than collapsed height"))

(fn test-expanded-details-layout-below-summary []
  (local ctx (make-test-ctx))
  (local (summary-builder summary-state) (make-instrumented-widget "summary" {:measure (glm.vec3 4 1 0)}))
  (local (details-builder details-state) (make-instrumented-widget "details" {:measure (glm.vec3 4 2 0)}))
  (local instance
    ((DisclosureRow {:summary summary-builder
                     :details details-builder
                     :expanded? true})
     ctx))
  (instance.layout:measurer)
  (set instance.layout.size instance.layout.measure)
  (set instance.layout.position (glm.vec3 10 20 0))
  (instance.layout:layouter)
  (assert (= summary-state.received-position.y 22)
          "summary should stay at the visual top of the disclosure")
  (assert (= details-state.received-position.y 20)
          "details should expand visually below the summary in y-up coordinates")
  (assert (< details-state.received-position.y summary-state.received-position.y)
          "details y should be lower than summary y")
  (instance:drop))

(fn test-collapsed-removes-details-layout []
  (local ctx (make-test-ctx))
  (local (summary-builder _) (make-instrumented-widget "summary"))
  (local (details-builder _) (make-instrumented-widget "details"))
  (local instance
    ((DisclosureRow {:summary summary-builder
                     :details details-builder
                     :expanded? true})
     ctx))
  (assert (= (length instance.layout.children) 2)
          "expanded disclosure should include details layout")
  (instance:set-expanded false)
  (assert (= (length instance.layout.children) 1)
          "collapsed disclosure should remove details layout")
  (instance:set-expanded true)
  (assert (= (length instance.layout.children) 2)
          "expanded disclosure should reattach details layout")
  (instance:drop))

(fn test-collapse-drops-details-widget []
  (local ctx (make-test-ctx))
  (local (summary-builder _) (make-instrumented-widget "summary"))
  (local (details-builder details-state) (make-instrumented-widget "details"))
  (local instance
    ((DisclosureRow {:summary summary-builder
                     :details details-builder
                     :expanded? true})
     ctx))
  (assert (= details-state.builder-count 1)
          "expanded disclosure should build details")
  (instance:set-expanded false)
  (assert (= details-state.drop-count 1)
          "collapsed disclosure should drop details widget")
  (instance:set-expanded true)
  (assert (= details-state.builder-count 2)
          "re-expanded disclosure should rebuild details widget")
  (instance:drop)
  (assert (= details-state.drop-count 2)
          "dropping re-expanded disclosure should drop current details widget"))

(table.insert tests {:name "DisclosureRow requires :summary"
                     :fn test-requires-summary})
(table.insert tests {:name "DisclosureRow constructs successfully"
                     :fn test-constructs-successfully})
(table.insert tests {:name "DisclosureRow drop cascades to children"
                     :fn test-drop-cascades})
(table.insert tests {:name "DisclosureRow expanded state toggles"
                     :fn test-expanded-state})
(table.insert tests {:name "DisclosureRow on-toggle callback fires"
                     :fn test-on-toggle-callback})
(table.insert tests {:name "DisclosureRow measure expanded vs collapsed"
                     :fn test-measure-expanded-vs-collapsed})
(table.insert tests {:name "DisclosureRow lays details below summary"
                     :fn test-expanded-details-layout-below-summary})
(table.insert tests {:name "DisclosureRow collapsed removes details layout"
                     :fn test-collapsed-removes-details-layout})
(table.insert tests {:name "DisclosureRow collapse drops details widget"
                     :fn test-collapse-drops-details-widget})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "disclosure-row"
                     :tests tests}))

{:tests tests
 :main main}

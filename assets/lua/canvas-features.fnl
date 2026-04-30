(local default-feature-id "graph")
(local persisted-feature-migrations {})

(local ordered-feature-specs
  [{:id "graph"
    :label "Graph"
    :icon "account_tree"
    :button-name "graph-canvas-feature"
    :show-in-sidebar? true
    :root-context-actions-key :graph
    :graph-interaction? true}
   {:id "drawing"
    :label "Draw"
    :icon "draw"
    :button-name "drawing-canvas-feature"
    :show-in-sidebar? true
    :root-context-actions-key :drawing
    :selection-context-actions-key :drawing-selection
    :drawing-controller? true
    :drawing-sidebar? true}])

(local feature-specs {})

(fn assert-feature-spec-shape! [feature-spec]
  (local feature-id (assert (. feature-spec :id) "Canvas feature spec requires :id"))
  (assert (= (type feature-id) :string)
          (.. "Canvas feature id must be a string, got " (type feature-id)))
  (when (= (. feature-spec :show-in-sidebar?) true)
    (assert (. feature-spec :icon)
            (.. "Canvas feature " feature-id " requires :icon when shown in sidebar"))
    (assert (. feature-spec :button-name)
            (.. "Canvas feature " feature-id " requires :button-name when shown in sidebar"))
    (assert (. feature-spec :label)
            (.. "Canvas feature " feature-id " requires :label when shown in sidebar")))
  feature-spec)

(each [_ feature-spec (ipairs ordered-feature-specs)]
  (assert-feature-spec-shape! feature-spec)
  (local feature-id (. feature-spec :id))
  (assert (not (. feature-specs feature-id))
          (.. "Duplicate canvas feature id: " feature-id))
  (set (. feature-specs feature-id) feature-spec))

(assert (. feature-specs default-feature-id)
        (.. "Default canvas feature missing from ordered specs: " default-feature-id))

(fn resolve [feature]
  (if (= feature nil)
      default-feature-id
      (do
        (assert (= (type feature) :string)
                (.. "Canvas feature id must be a string, got " (type feature)))
        (assert (. feature-specs feature)
                (.. "Unknown canvas feature: " feature))
        feature)))

(fn spec [feature]
  (. feature-specs (resolve feature)))

(fn feature-specs-in-order []
  (local ordered [])
  (each [_ feature-spec (ipairs ordered-feature-specs)]
    (table.insert ordered feature-spec))
  ordered)

(fn sidebar-feature-specs []
  (local sidebar-features [])
  (each [_ feature-spec (ipairs (feature-specs-in-order))]
    (when (= (and feature-spec (. feature-spec :show-in-sidebar?)) true)
      (table.insert sidebar-features feature-spec)))
  sidebar-features)

(fn matches-id? [feature id]
  (= (resolve feature) (resolve id)))

(fn supports-graph-interaction? [feature]
  (local feature-spec (spec feature))
  (= (and feature-spec (. feature-spec :graph-interaction?)) true))

(fn supports-drawing-controller? [feature]
  (local feature-spec (spec feature))
  (= (and feature-spec (. feature-spec :drawing-controller?)) true))

(fn supports-drawing-sidebar? [feature]
  (local feature-spec (spec feature))
  (= (and feature-spec (. feature-spec :drawing-sidebar?)) true))

(fn normalize-persisted [feature]
  (if (= feature nil)
      (values default-feature-id false nil)
      (if (and (= (type feature) :string)
               (. feature-specs feature))
          (values feature false nil)
          (do
            (local migrated (. persisted-feature-migrations feature))
            (if migrated
                (values migrated
                        true
                        (.. "migrating persisted canvas.active_feature from "
                            (tostring feature)
                            " to "
                            migrated))
                (values default-feature-id
                        true
                        (.. "invalid persisted canvas.active_feature "
                            (tostring feature)
                            "; resetting to "
                            default-feature-id)))))))

{:default-feature-id default-feature-id
 :feature-specs-in-order feature-specs-in-order
 :sidebar-feature-specs sidebar-feature-specs
 :matches-id? matches-id?
 :normalize-persisted normalize-persisted
 :resolve resolve
 :spec spec
 :supports-graph-interaction? supports-graph-interaction?
 :supports-drawing-controller? supports-drawing-controller?
 :supports-drawing-sidebar? supports-drawing-sidebar?}

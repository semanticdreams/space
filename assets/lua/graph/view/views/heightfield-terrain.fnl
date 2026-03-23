(local Validation (require :graph/heightfield-terrain-editor-validation))
(local PerlinValidation (require :graph/heightfield-perlin-tool-validation))
(local ScrollView (require :scroll-view))
(local {: Flex : FlexChild} (require :flex))
(local TerrainEditorFormView (require :graph/terrain-editor-form-view))

(fn HeightfieldTerrainNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "HeightfieldTerrainNodeView requires a build context")
    (var perlin-draft (PerlinValidation.draft-from-record nil))
    (local flat-target {:terrain-id (and target target.terrain-id)
                        :changed (and target target.changed)
                        :get-record (fn []
                                      (and target target.get-record (target:get-record)))
                        :apply-values (fn [_self draft-values]
                                        (and target target.apply-values (target:apply-values draft-values)))})
    (local perlin-target {:terrain-id (and target target.terrain-id)
                          :changed (and target target.changed)
                          :get-record (fn []
                                        (and target target.get-record (target:get-record)))
                          :apply-values (fn [_self draft-values]
                                          (and target target.apply-perlin-values
                                               (target:apply-perlin-values draft-values)))})
    (local flat-view
      ((TerrainEditorFormView flat-target {:validation Validation
                                           :name "heightfield-flat-tool-view"
                                           :wrap-scroll? false
                                           :info-text (.. "Initialize heightfield terrain "
                                                          (or (and target target.terrain-id) "?")
                                                          " to a flat height")})
       build-ctx))
    (local perlin-view
      ((TerrainEditorFormView perlin-target {:validation PerlinValidation
                                             :name "heightfield-perlin-tool-view"
                                             :wrap-scroll? false
                                             :refresh-on-change? false
                                             :read-baseline-draft (fn []
                                                                    perlin-draft)
                                             :write-baseline-draft (fn [draft]
                                                                     (set perlin-draft draft))
                                             :info-text (.. "Apply perlin to heightfield terrain "
                                                            (or (and target target.terrain-id) "?"))})
       build-ctx))
    (local content
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.5
              :children [(FlexChild (fn [_] flat-view) 0)
                         (FlexChild (fn [_] perlin-view) 0)]})
       build-ctx))
    (local scroll-view
      ((ScrollView {:child (fn [_] content)
                    :padding false
                    :scrollbar-policy :as-needed
                    :name "heightfield-terrain-node-view"})
       build-ctx))
    {:layout scroll-view.layout
     :scroll-view scroll-view
     :flat-view flat-view
     :perlin-view perlin-view
     :drop (fn [_self]
             (scroll-view:drop))}))

HeightfieldTerrainNodeView

(local DefaultDialog (require :default-dialog))
(local Input (require :input))
(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))
(local PanelUtils (require :target-panel-utils))

(fn trim-text [value]
    (var trimmed (string.gsub (or value "") "^%s+" ""))
    (set trimmed (string.gsub trimmed "%s+$" ""))
    trimmed)

(fn AddToMapDialog [opts]
    (local options (or opts {}))
    (local graph-map-provider options.graph-map-provider)
    (local fallback-graph-map options.graph-map)
    (assert (or graph-map-provider fallback-graph-map)
            "AddToMapDialog requires :graph-map or :graph-map-provider")

    (fn current-graph-map []
        (local graph-map (or (and graph-map-provider (graph-map-provider))
                             fallback-graph-map))
        (assert graph-map "Add to Map requires an active graph map")
        graph-map)

    (fn build [ctx runtime-opts]
        (var input nil)

        (fn add-key-to-map []
            (local key (trim-text (input:get-text)))
            (assert (> (string.len key) 0) "Add to Map requires a graph key")
            (local graph-map (current-graph-map))
            (local node (graph-map:load-by-key key))
            (assert node (.. "Add to Map could not resolve graph key: " key))
            node)

        (local child-builder
              (fn [child-ctx]
                  (set input
                       ((Input {:name "add-to-map-key"
                                :placeholder "Graph key, e.g. fs:/tmp"})
                        child-ctx))
                  (local add-button
                        ((Button {:text "Add to Map"
                                  :variant :primary
                                  :on-click (fn [_button _event]
                                              (add-key-to-map))})
                         child-ctx))
                  ((Flex {:axis 2
                          :xalign :stretch
                          :yspacing 0.45
                          :children [(FlexChild (fn [_] input) 0)
                                     (FlexChild (fn [_] add-button) 0)]})
                   child-ctx)))

        (local dialog
              ((DefaultDialog {:title "Add to Map"
                               :name "add-to-map-dialog"
                               :child child-builder
                               :transfer-builder (AddToMapDialog options)})
               ctx
               runtime-opts))
        (set dialog.input input)
        (set dialog.add-key-to-map (fn [_self] (add-key-to-map)))
        dialog))

(fn open-panel [opts]
    (local options (or opts {}))
    (local target (assert (or options.target options.hud)
                          "Add to Map requires target"))
    (assert target.add-panel-child "Add to Map target requires :add-panel-child")
    (local graph-map-provider options.graph-map-provider)
    (local graph-map options.graph-map)
    (assert (or graph-map-provider graph-map)
            "Add to Map requires :graph-map or :graph-map-provider")
    (local placement (PanelUtils.panel-placement-options target options.panel))
    (target:add-panel-child {:builder (AddToMapDialog {:graph-map graph-map
                                                       :graph-map-provider graph-map-provider})
                             :location placement.location
                             :align-x placement.align-x
                             :align-y placement.align-y
                             :position placement.position
                             :rotation placement.rotation
                             :size placement.size}))

{:AddToMapDialog AddToMapDialog
 :open-panel open-panel}

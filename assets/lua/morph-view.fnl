(local DefaultDialog (require :default-dialog))
(local SearchView (require :search-view))
(local {: Flex : FlexChild} (require :flex))
(local Text (require :text))
(local Button (require :button))
(local Morphs (require :morphs/init))

(fn display-node [node]
  (if (and node node.key)
      (or node.label node.key)
      "None"))

(fn selected-source-node []
  (local selected (or (and app app.graph-view app.graph-view.selection
                           app.graph-view.selection.selected-nodes)
                      []))
  (if (= (length selected) 1)
      (. selected 1)
      nil))

(fn MorphView [opts]
  (local options (or opts {}))

  (fn build [ctx runtime-opts]
    (local run-options (or runtime-opts options))
    (local morphs (or run-options.morphs (Morphs.get-default)))
    (local title (or run-options.title "Morphs"))
    (local name (or run-options.name "morph-view"))
    (var selection-handler nil)
    (var morph-handler nil)

    (fn build-content [child-ctx]
      (local source-text ((Text {:text "Source: select exactly one node"}) child-ctx))
      (local status-text ((Text {:text ""}) child-ctx))
      (var current-source nil)

      (local search
        ((SearchView {:items []
                      :name "morph-view-search"
                      :placeholder "Select morph target"
                      :num-per-page 8
                      :builder (fn [item search-ctx]
                                 (local entry (and item (. item 1)))
                                 (local label (tostring (or (and entry entry.label) (. item 2) "")))
                                 ((Button {:text label
                                           :variant :ghost
                                           :on-click (fn [_button _event]
                                                       (when (and current-source entry)
                                                         (local (ok err)
                                                           (pcall (fn []
                                                                    (morphs:apply current-source entry.to-scheme {}))))
                                                         (if ok
                                                             (status-text:set-text (.. "Morphed to " entry.to-scheme))
                                                             (status-text:set-text (.. "Morph failed: " err)))))})
                                  search-ctx))})
         child-ctx))

      (fn refresh-source []
        (set current-source (selected-source-node))
        (if current-source
            (source-text:set-text (.. "Source: " (display-node current-source)))
            (source-text:set-text "Source: select exactly one node"))
        (local items (if current-source
                         (morphs:target-items current-source)
                         []))
        (search:set-items items))

      (local selected-signal
        (and app app.graph-view app.graph-view.selection
             app.graph-view.selection.selected-nodes-changed))
      (when selected-signal
        (set selection-handler
             (selected-signal:connect
               (fn [_nodes]
                 (refresh-source)))))

      (when (and morphs morphs.morphed)
        (set morph-handler
             (morphs.morphed:connect
               (fn [_payload]
                 (refresh-source)))))

      (refresh-source)

      (local content
        ((Flex {:axis 2
                :xalign :stretch
                :yspacing 0.4
                :children [(FlexChild (fn [_] source-text) 0)
                           (FlexChild (fn [_] status-text) 0)
                           (FlexChild (fn [_] search) 1)]})
         child-ctx))

      {:layout content.layout
       :drop (fn [_self]
               (when (and selected-signal selection-handler)
                 (selected-signal:disconnect selection-handler true)
                 (set selection-handler nil))
               (when (and morphs morphs.morphed morph-handler)
                 (morphs.morphed:disconnect morph-handler true)
                 (set morph-handler nil))
               (source-text:drop)
               (status-text:drop)
               (search:drop)
               (content:drop))})

    ((DefaultDialog {:title title
                     :name name
                     :on-close run-options.on-close
                     :child build-content})
     ctx))

  build)

MorphView

(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Input (require :input))
(local ListView (require :list-view))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Utils (require :graph/view/utils))

(fn build-item-rows [items]
  (local total (length (or items [])))
  (icollect [i k (ipairs (or items []))]
    {:index i
     :total total
     :key (tostring k)}))

(fn key-scheme [key]
  (when (and key (= (type key) "string"))
    (local (start _end) (string.find key ":" 1 true))
    (if start
        (string.sub key 1 (- start 1))
        key)))

(fn type-label-from-key [key]
  (local scheme (or (key-scheme key) "unknown"))
  (tostring scheme))

(fn resolve-preview-node [target item-key]
  (local graph (and target target.graph))
  (if (not graph)
      nil
      (if graph.resolve-node
          (do
            (local (ok resolved) (pcall (fn [] (graph:resolve-node item-key))))
            (if ok resolved nil))
          (or (graph:lookup item-key)
              (if graph.load-by-key
                  (do
                    (local (ok loaded) (pcall (fn [] (graph:load-by-key item-key))))
                    (if ok loaded nil))
                  nil)))))

(fn build-preview-widget [target item-key child-ctx]
  (local resolved (resolve-preview-node target item-key))
  (if (not resolved)
      (values ((Text {:text (Utils.truncate-with-ellipsis item-key 42)})
               child-ctx)
              nil)
      (do
        (assert resolved.preview (.. "Resolved notebook item is missing preview: " (tostring item-key)))
        (local preview-widget
          ((resolved.preview resolved {:node resolved}) child-ctx))
        (assert (and preview-widget preview-widget.layout)
                (.. "Notebook preview builder must return widget with layout for " (tostring item-key)))
        (values preview-widget resolved))))

(fn NotebookNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "NotebookNodeView requires a build context")
    (local view {})
    (local notebook (and target target.get-notebook (target:get-notebook)))

    (local name-input
      ((Input {:text ""
               :placeholder "Notebook name..."
               :on-change (fn [_input new-value]
                            (when (and target target.update-name)
                              (target:update-name new-value)))})
       build-ctx))
    (local initial-name (or (and notebook notebook.name) ""))
    (when (and name-input name-input.set-text (> (string.len initial-name) 0))
      (name-input:set-text initial-name {:reset-cursor? false}))

    (local items-label
      ((Text {:text ""
              :name "notebook-items-label"
              :color (glm.vec4 0.9 0.9 0.9 1)})
       build-ctx))

    (local list
      ((ListView {:name "notebook-items"
                  :items []
                  :scroll true
                  :paginate false
                  :show-head false
                  :item-spacing 0.25
                  :builder (fn [item child-ctx]
                             (local item-key (tostring (or item.key "")))
                             (local index (tonumber (or item.index 1)))
                             (local total (tonumber (or item.total 0)))
                             (local (preview-widget resolved-node)
                                    (build-preview-widget target item-key child-ctx))
                             (local type-label
                                    (if (and resolved-node resolved-node.key)
                                        (type-label-from-key resolved-node.key)
                                        (type-label-from-key item-key)))

                             (local type-text
                               ((Text {:text type-label
                                       :style (TextStyle {:scale 0.9
                                                          :color (glm.vec4 0.75 0.75 0.75 1)})})
                                child-ctx))

                             (local up-button
                               ((Button {:icon "expand_less"
                                         :variant :ghost
                                         :padding [0.12 0.12]
                                         :on-click (fn [_button _event]
                                                     (when (and target target.move-item (> index 1))
                                                       (target:move-item index (- index 1))))})
                                child-ctx))

                             (local down-button
                               ((Button {:icon "expand_more"
                                         :variant :ghost
                                         :padding [0.12 0.12]
                                         :on-click (fn [_button _event]
                                                     (when (and target target.move-item (< index total))
                                                       (target:move-item index (+ index 1))))})
                                child-ctx))

                             (local remove-button
                               ((Button {:icon "delete"
                                         :variant :ghost
                                         :padding [0.12 0.12]
                                         :on-click (fn [_button _event]
                                                     (when (and target target.remove-item)
                                                       (target:remove-item item-key)))})
                                child-ctx))

                             (local controls
                               ((Flex {:axis 2
                                       :xalign :stretch
                                       :yspacing 0
                                       :children [(FlexChild (fn [_] up-button) 0)
                                                  (FlexChild (fn [_] down-button) 0)
                                                  (FlexChild (fn [_] remove-button) 0)]})
                                child-ctx))

                             (local content-row
                               ((Flex {:axis 1
                                       :yalign :stretch
                                       :children [(FlexChild (fn [_] controls) 0)
                                                  (FlexChild (fn [_] preview-widget) 1)]})
                                child-ctx))

                             ((Flex {:axis 2
                                     :xalign :stretch
                                     :yspacing 0
                                     :children [(FlexChild (fn [_] type-text) 0)
                                                (FlexChild (fn [_] content-row) 1)]})
                              child-ctx))})
       build-ctx))

    (local add-selected-button
      ((Button {:icon "playlist_add"
                :text "Add Selected"
                :variant :ghost
                :on-click (fn [_button _event]
                            (local selected (or (and app.graph-view
                                                     app.graph-view.selection
                                                     app.graph-view.selection.selected-nodes)
                                                []))
                            (each [_ selected-node (ipairs selected)]
                              (local key (or (and selected-node selected-node.key) nil))
                              (when (and key target target.add-item)
                                (target:add-item key))))})
       build-ctx))

    (local add-string-entity-button
      ((Button {:icon "add"
                :text "Add String Entity"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.add-string-entity)
                              (target:add-string-entity {})))})
       build-ctx))

    (local delete-button
      ((Button {:icon "delete"
                :text "Delete Notebook"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.delete-notebook)
                              (target:delete-notebook)))})
       build-ctx))

    (local actions-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_] add-selected-button) 0)
                         (FlexChild (fn [_] add-string-entity-button) 0)
                         (FlexChild (fn [_] delete-button) 0)]})
       build-ctx))

    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.4
              :children [(FlexChild (fn [_] name-input) 0)
                         (FlexChild (fn [_] items-label) 0)
                         (FlexChild (fn [_] list) 1)
                         (FlexChild (fn [_] actions-row) 0)]})
       build-ctx))

    (set view.name-input name-input)
    (set view.items-label items-label)
    (set view.list list)
    (set view.actions-row actions-row)
    (set view.layout flex.layout)

    (set view.refresh-items
         (fn [self]
           (local current (and target target.get-notebook (target:get-notebook)))
           (local items (or (and current current.items) []))
           (local count (length items))
           (when (and self.items-label self.items-label.set-text)
             (self.items-label:set-text (.. "Items (" count "):")))
           (when (and self.list self.list.set-items)
             (self.list:set-items (build-item-rows items)))))

    (local items-signal (and target target.items-changed))
    (local items-handler (fn [_payload] (view:refresh-items)))
    (when items-signal
      (items-signal:connect items-handler))

    (set view.drop
         (fn [_self]
           (when items-signal
             (items-signal:disconnect items-handler true))
           (flex:drop)))

    (view:refresh-items)
    view))

NotebookNodeView

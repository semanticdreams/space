(local glm (require :glm))
(local Button (require :button))
(local Card (require :card))
(local ListView (require :list-view))
(local Padding (require :padding))
(local Text (require :text))
(local TextStyle (require :text-style))
(local TextUtils (require :text-utils))
(local {: Flex : FlexChild} (require :flex))
(local {: Layout} (require :layout))
(local Signal (require :signal))

(fn normalize-item [entry]
    (if (= (type entry) :table)
        (do
            (local value
                (if (not (= (. entry :value) nil))
                    (. entry :value)
                    (if (not (= (. entry :key) nil))
                        (. entry :key)
                        (. entry 1))))
            (local label
                (or (. entry :label)
                    (. entry :text)
                    (. entry :name)
                    (. entry 2)
                    (tostring value)))
            {:value value :label label})
        (do
            (local label (tostring entry))
            {:value entry :label label})))

(fn normalize-items [items]
    (local normalized [])
    (each [_ entry (ipairs (or items []))]
        (table.insert normalized (normalize-item entry)))
    normalized)

(fn find-item [items value]
    (var found nil)
    (each [_ item (ipairs (or items []))]
        (when (and (not found) (= item.value value))
            (set found item)))
    found)

(fn resolve-selected [items options]
    (local explicit (or (. options :selected) (. options :value)))
    (if (and (= (type explicit) :table) (not (= (. explicit :value) nil)))
        (find-item items (. explicit :value))
        (if (not (= explicit nil))
            (find-item items explicit)
            nil)))

(fn ComboBox [opts]
    (local options (or opts {}))
    (local items (normalize-items options.items))
    (local placeholder (or options.placeholder "Select"))
    (local max-menu-height options.max-menu-height)
    (local selected (resolve-selected items options))

    (fn build [ctx]
        (local icons (assert ctx.icons "ComboBox requires ctx.icons"))
        (local theme (and ctx ctx.theme))
        (local combo-theme (and theme theme.combo-box))
        (local items-per-page
            (or options.items-per-page
                options.max-visible-items
                (and combo-theme combo-theme.items-per-page)
                10))
        (local arrow-code (icons:get "arrow_drop_down"))
        (local view {:items items
                     :selected selected
                     :open? false
                     :changed (Signal)
                     :button nil
                     :list nil})

        (fn resolve-label []
            (if view.selected
                view.selected.label
                placeholder))

        (fn update-button-label []
            (local label (resolve-label))
            (when (and view.label-text view.label-text.set-text)
                (view.label-text:set-text label)))

        (fn set-selected [self value emit?]
            (local next-item
                (if (and (= (type value) :table) (not (= (. value :value) nil)))
                    (find-item self.items (. value :value))
                    (if (not (= value nil))
                        (find-item self.items value)
                        nil)))
            (local previous (and self.selected self.selected.value))
            (local next-value (and next-item next-item.value))
            (set self.selected next-item)
            (update-button-label)
            (when (and emit? (not (= previous next-value)))
                (self.changed:emit next-value)))

        (fn set-items [self new-items]
            (set self.items (normalize-items new-items))
            (when self.list-view
                (self.list-view:set-items self.items))
            (when self.selected
                (if (not (find-item self.items self.selected.value))
                    (set-selected self nil false)))
            (update-button-label))

        (var focus-listener nil)
        (var set-open nil)
        (fn node-in-scope? [node scope]
            (var current node)
            (var found false)
            (while (and current (not found))
                (when (= current scope)
                    (set found true))
                (set current current.parent))
            found)
        (fn attach-list-focus-scope []
            (local list-view view.list-view)
            (local focus-context (and list-view list-view.focus-context))
            (local scope (and list-view list-view.focus-scope))
            (when (and focus-context scope (not scope.parent))
                (focus-context:attach scope)))
        (fn detach-list-focus-scope []
            (local list-view view.list-view)
            (local focus-context (and list-view list-view.focus-context))
            (local scope (and list-view list-view.focus-scope))
            (when (and focus-context scope scope.parent)
                (local manager focus-context.manager)
                (local current (and manager (manager:get-focused-node)))
                (when (and current view.button (node-in-scope? current scope))
                    (view.button:request-focus))
                (focus-context:detach scope)))

        (fn unregister-focus-listener []
            (when (and focus-listener
                       view.button
                       view.button.focus-manager
                       view.button.focus-manager.focus-blur)
                (view.button.focus-manager.focus-blur.disconnect focus-listener true)
                (set focus-listener nil)))

        (fn register-focus-listener []
            (when (and (not focus-listener)
                       view.button
                       view.button.focus-manager
                       view.button.focus-manager.focus-blur)
                (set focus-listener
                     (view.button.focus-manager.focus-blur.connect
                       (fn [event]
                           (local previous (and event event.previous))
                           (when (and view.open?
                                      view.button
                                      (= previous view.button.focus-node))
                               (set-open view false)))))))

        (fn apply-open-state [self desired]
            (set self.open? desired)
            (if desired
                (do
                    (when (and self.button self.button.request-focus)
                        (self.button:request-focus))
                    (attach-list-focus-scope)
                    (register-focus-listener))
                (do
                    (detach-list-focus-scope)
                    (unregister-focus-listener)))
            (when (and self.layout self.layout.mark-measure-dirty)
                (self.layout:mark-measure-dirty))
            (when (and self.layout self.layout.mark-layout-dirty)
                (self.layout:mark-layout-dirty)))

        (fn update-open-state [self open?]
            (local desired (and open? true))
            (when (not (= self.open? desired))
                (apply-open-state self desired)))

        (set set-open update-open-state)

        (fn toggle-open [self]
            (local next-state (not self.open?))
            (set-open self next-state))

        (fn on-item-selected [item]
            (set-selected view item true)
            (set-open view false))

        (var label-text nil)
        (var icon-text nil)
        (local content-builder
            (fn [child-ctx]
                (set label-text ((Text {:text (resolve-label)}) child-ctx))
                (local icon-color (or (TextUtils.get-theme-text-color child-ctx)
                                      (glm.vec4 1 0 0 1)))
                (set icon-text ((Text {:codepoints [arrow-code]
                                       :style (TextStyle {:font icons.font
                                                          :color icon-color})})
                                child-ctx))
                ((Padding {:edge-insets (or options.padding [0.5 0.5])
                           :child (Flex {:axis :x
                                         :xspacing (or options.content-spacing 0.35)
                                         :yalign :center
                                         :children [(FlexChild (fn [_] label-text) 1)
                                                    (FlexChild (fn [_] icon-text) 0)]})})
                 child-ctx)))

        (local button
            ((Button {:name (or options.name "combo-box")
                      :child content-builder
                      :on-click (fn [_button _event]
                                      (toggle-open view))})
             ctx))

        (local list-builder
            (ListView {:items view.items
                       :name (.. (or options.name "combo-box") "-list")
                       :scroll true
                       :show-head false
                       :paginate false
                       :item-spacing 0
                       :fill-width true
                       :scrollbar-policy :as-needed
                       :scroll-items-per-page (if max-menu-height nil items-per-page)
                       :viewport-height max-menu-height
                       :builder (fn [item child-ctx]
                                   ((Button {:text item.label
                                             :variant :ghost
                                             :on-click (fn [_btn _event]
                                                             (on-item-selected item))})
                                    child-ctx))}))

        (local list-view (list-builder ctx))
        (local list
            ((Card {:child (fn [_ctx] list-view)
                    :name (.. (or options.name "combo-box") "-card")})
             ctx))

        (fn measurer [self]
            (button.layout:measurer)
            (list.layout:measurer)
            (local button-measure button.layout.measure)
            (local list-measure list.layout.measure)
            (local width button-measure.x)
            (local height button-measure.y)
            (local depth (math.max button-measure.z list-measure.z))
            (set self.measure (glm.vec3 width height depth)))

        (fn layouter [self]
            (local button-measure button.layout.measure)
            (local width (math.max self.size.x button-measure.x))
            (local button-size (glm.vec3 width button-measure.y self.size.z))
            (set button.layout.size button-size)
            (set button.layout.position self.position)
            (set button.layout.rotation self.rotation)
            (set button.layout.depth-offset-index self.depth-offset-index)
            (set button.layout.clip-region self.clip-region)
            (button.layout:layouter)
            (local list-height (if view.open? list.layout.measure.y 0))
            (local list-width (math.max width list.layout.measure.x))
            (set list.layout.size (glm.vec3 list-width list-height self.size.z))
            (set list.layout.position (+ self.position
                                         (glm.vec3 0 (- list-height) 0)))
            (set list.layout.rotation self.rotation)
            (set list.layout.depth-offset-index (+ self.depth-offset-index 10))
            (set list.layout.clip-region nil)
            (list.layout:layouter))

        (local layout
            (Layout {:name (or options.name "combo-box")
                     :children [button.layout list.layout]
                     :measurer measurer
                     :layouter layouter}))

        (set view.button button)
        (set view.list list)
        (set view.list-view list-view)
        (set view.label-text label-text)
        (set view.layout layout)
        (detach-list-focus-scope)
        (set view.set-items set-items)
        (set view.set-selected (fn [self value] (set-selected self value true)))
        (set view.set-value (fn [self value] (set-selected self value true)))
        (set view.get-value (fn [self] (and self.selected self.selected.value)))
        (set view.get-label (fn [self] (resolve-label)))
        (set view.open (fn [self] (set-open self true)))
        (set view.close (fn [self] (set-open self false)))
        (set view.toggle (fn [self] (toggle-open self)))
        (set view.drop
             (fn [_self]
                 (unregister-focus-listener)
                 (button:drop)
                 (list:drop)
                 (layout:drop)
                 (view.changed:clear)))

        view))

ComboBox

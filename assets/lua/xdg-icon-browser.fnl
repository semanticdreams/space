(local {: Grid} (require :grid))
(local {: Flex : FlexChild} (require :flex))
(local {: Layout} (require :layout))
(local Button (require :button))
(local Input (require :input))
(local ComboBox (require :combo-box))
(local ListView (require :list-view))
(local Padding (require :padding))
(local ScrollView (require :scroll-view))
(local Text (require :text))
(local TextStyle (require :text-style))
(local TextUtils (require :text-utils))
(local Image (require :image))
(local Sized (require :sized))
(local textures (require :textures))
(local fs (require :fs))
(local json (require :json))
(local StringUtils (require :string-utils))
(local glm (require :glm))

(local fuzzy-match StringUtils.fuzzy-match)

(fn load-icons []
    (local path (app.engine.get-asset-path "data/xdg-icons.json"))
    (local content (fs.read-file path))
    (if content
        (do
            (local (ok result) (pcall json.loads content))
            (if ok result {}))
        {}))

(fn list-contains? [items value]
    (var found false)
    (each [_ item (ipairs (or items []))]
        (when (= item value)
            (set found true)))
    found)

(fn resolve-default [items preferred fallback]
    (if (list-contains? items preferred)
        preferred
        (or (. items 1) fallback)))

(fn normalize-context [value]
    (if (not value)
        nil
        (if (or (string.match value "^%d")
                (string.match value "^scalable%-"))
            (or (string.match value ".*%-(.+)$") value)
            value)))

(fn svg-path? [path]
    (and path (string.match path "%.svg$")))

(fn supported-image-path? [path]
    (and path
         (or (string.match path "%.png$")
             (string.match path "%.xpm$"))))

(fn resolve-theme-path [icon-data theme]
    (local paths (and icon-data icon-data.paths))
    (local theme-paths (and paths theme))
    (var found nil)
    (when theme-paths
        (when (and (= (type theme-paths) :string)
                   (supported-image-path? theme-paths))
            (set found theme-paths))
        (each [_ key (ipairs ["32" "24" "48" "16" "64" "128" "256" "512"])]
            (when (not found)
                (local candidate (. theme-paths key))
                (when (supported-image-path? candidate)
                    (set found candidate))))
        (when (= (type theme-paths) :table)
            (each [_ value (pairs theme-paths)]
                (when (and (not found)
                           (supported-image-path? value))
                    (set found value)))))
    found)

(fn resolve-icon-path [icon-data theme]
    (local themed (resolve-theme-path icon-data theme))
    (if themed
        themed
        (do
            (var found nil)
            (each [_ fallback (ipairs (or icon-data.themes []))]
                (when (not found)
                    (local fallback-path (resolve-theme-path icon-data fallback))
                    (when fallback-path
                        (set found fallback-path))))
            found)))

(fn IconGrid [opts]
    (local options (or opts {}))

    (fn build [ctx]
        (local columns (math.max 1 (or options.columns 6)))
        (local xspacing (or options.xspacing 0.6))
        (local yspacing (or options.yspacing 0.6))
        (var grid nil)
        (local layout
            (Layout {:name "icon-grid-container"
                     :measurer (fn [self]
                                   (if grid
                                       (do
                                           (grid.layout:measurer)
                                           (set self.measure grid.layout.measure))
                                       (set self.measure (glm.vec3 0 0 0))))
                     :layouter (fn [self]
                                   (when grid
                                       (local child-layout grid.layout)
                                       (local content-size (or child-layout.measure (glm.vec3 0 0 0)))
                                       (local y-offset (math.max 0 (- self.size.y content-size.y)))
                                       (set child-layout.size
                                            (glm.vec3 self.size.x
                                                      content-size.y
                                                      self.size.z))
                                       (set child-layout.position
                                            (+ self.position
                                               (self.rotation:rotate (glm.vec3 0 y-offset 0))))
                                       (set child-layout.rotation self.rotation)
                                       (set child-layout.depth-offset-index self.depth-offset-index)
                                       (set child-layout.clip-region self.clip-region)
                                       (child-layout:layouter)))}))

        (fn build-empty-cell [cell-ctx]
            (local cell-layout
                (Layout {:name "icon-grid-empty"
                         :measurer (fn [self] (set self.measure (glm.vec3 0 0 0)))
                         :layouter (fn [_self] nil)}))
            {:layout cell-layout
             :drop (fn [_self] (cell-layout:drop))})

        (fn build-grid [items]
            (local source (or items []))
            (local count (length source))
            (local rows (math.max 1 (math.ceil (/ (math.max count 1) columns))))
            (local target-count (* rows columns))
            (local ordered {})
            (for [i 1 target-count] (set (. ordered i) nil))
            (for [idx 1 count]
                (local zero-based (- idx 1))
                (local row (math.floor (/ zero-based columns)))
                (local col (math.fmod zero-based columns))
                (local target (+ (* col rows) row 1))
                (set (. ordered target) (. source idx)))
            (local children [])
            (local label-color (or (TextUtils.get-theme-text-color ctx)
                                   (glm.vec4 1 1 1 1)))
            (each [_ icon-data (ipairs ordered)]
                (local child
                    (if icon-data
                        (let [icon-name (or icon-data.name icon-data.icon)
                              icon-path icon-data.path
                              loader (or (and textures textures.load-texture-async)
                                         (and textures textures.load-texture))
                              texture (and loader icon-path
                                           (loader icon-path icon-path))]
                            (if texture
                                ((Sized {:size (glm.vec3 4.5 3.8 0)
                                         :child (fn [c]
                                                    ((Flex {:axis :y
                                                            :xalign :center
                                                            :yspacing 0.2
                                                            :children [(FlexChild (fn [cc]
                                                                                      ((Image {:texture texture
                                                                                               :size (glm.vec3 2.0 2.0 0)})
                                                                                       cc)) 0)
                                                                       (FlexChild (fn [cc]
                                                                                      ((Text {:text icon-name
                                                                                              :style (TextStyle {:scale 0.9
                                                                                                                 :color label-color})})
                                                                                       cc)) 0)]})
                                                     c))})
                                 ctx)
                                (build-empty-cell ctx)))
                        (build-empty-cell ctx)))
                (table.insert children {:widget (fn [_] child)
                                        :align-x :center
                                        :align-y :center}))
            ((Grid {:rows rows
                    :columns columns
                    :xmode :even
                    :ymode :even
                    :xspacing xspacing
                    :yspacing yspacing
                    :children children})
             ctx))

        (fn rebuild-grid [items]
            (when grid
                (grid:drop)
                (set grid nil))
            (set grid (build-grid items))
            (layout:set-children [grid.layout])
            (layout:mark-measure-dirty)
            (layout:mark-layout-dirty))

        (rebuild-grid options.items)

        {:layout layout
         :set-items (fn [_self items] (rebuild-grid items))
         :drop (fn [_self]
                   (when grid
                       (grid:drop)
                       (set grid nil))
                   (layout:drop))}))

(fn XdgIconBrowser [opts]
    (local options (or opts {}))
    (local icons-map (load-icons))
    (local all-themes {})
    (local all-contexts {})
    (local icons-list [])
    
    (each [name data (pairs icons-map)]
        (when (and data (not data.name))
            (set data.name name))
        (local normalized-contexts [])
        (table.insert icons-list data)
        (each [_ theme (ipairs (or data.themes []))]
            (tset all-themes theme true))
        (each [_ context (ipairs (or data.contexts []))]
            (local normalized (normalize-context context))
            (when normalized
                (table.insert normalized-contexts normalized)
                (tset all-contexts normalized true)))
        (set data.normalized-contexts normalized-contexts))
            
    (local theme-items [])
    (each [theme _ (pairs all-themes)]
        (table.insert theme-items theme))
    (table.sort theme-items)
    
    (local context-items [])
    (each [context _ (pairs all-contexts)]
        (table.insert context-items context))
    (table.sort context-items)

    (local default-theme (resolve-default theme-items "Adwaita" "hicolor"))
    (local default-context
        (resolve-default context-items
                         (or options.initial-context options.initial_context)
                         nil))

    (local state {:selected-context default-context
                  :last-context default-context
                  :search-query ""
                  :selected-theme default-theme
                  :filtered-icons []})

    (fn filter-icons [self]
        (local result [])
        (each [_ data (ipairs icons-list)]
            (var match? false)
            (local name (or data.name ""))
            (local themes (or data.themes []))
            (local contexts (or data.normalized-contexts []))
            (local resolved-path (resolve-icon-path data self.selected-theme))

            (local theme-match?
                (if (> (length themes) 0)
                    (list-contains? themes self.selected-theme)
                    true))

            (when (and theme-match? resolved-path)
                (if (and self.search-query (not (= self.search-query "")))
                    (when (fuzzy-match self.search-query name)
                        (set match? true))
                    (if self.selected-context
                        (when (list-contains? contexts self.selected-context)
                            (set match? true))
                        (set match? true))))
            
            (when match?
                (table.insert result {:name name :path resolved-path})))
        
        ;; Sort by name
        (table.sort result (fn [a b] (< a.name b.name)))
        (set self.filtered-icons result))

    (fn build [ctx]
        (var icon-grid nil)
        (var search-input nil)
        (var search-listener nil)
        (var theme-listener nil)
        (var update-view nil)
        
        (set update-view
            (fn []
                (filter-icons state)
                (when icon-grid
                    (icon-grid:set-items state.filtered-icons))))

        ;; Sidebar: Context List
    (local context-list-view
         ((ListView {:items (icollect [_ c (ipairs context-items)] {:label c :value c})
                     :items-per-page 20
                     :fill-width true
                     :reverse false
                     :scroll false
                     :show-head false
                     :builder (fn [item child-ctx]
                                ((Button {:text item.label
                                          :variant (if (= state.selected-context item.value) :primary :ghost)
                                          :on-click (fn [_ _] 
                                                      (set state.selected-context item.value)
                                                      (set state.last-context item.value)
                                                      (set state.search-query "")
                                                      (if (and search-input search-input.model)
                                                          (search-input.model:set-text "")
                                                          (update-view)))})
                                 child-ctx))})
          ctx))
    (local context-scroll-view
         ((ScrollView {:child (fn [_] context-list-view)
                       :scrollbar-policy :as-needed
                       :scroll-offset 0})
          ctx))
    (when (and context-scroll-view context-scroll-view.set-scroll-offset)
        (context-scroll-view:set-scroll-offset 0))

        ;; Top Bar: Search + Theme
        (set search-input
             ((Input {:placeholder "Search icons..."
                      :text state.search-query})
              ctx))

        (local theme-combo
             ((ComboBox {:items (icollect [_ t (ipairs theme-items)] {:label t :value t})
                         :selected state.selected-theme})
              ctx))

        (set icon-grid ((IconGrid {:items state.filtered-icons
                                   :columns 6
                                   :xspacing 0.8
                                   :yspacing 0.8})
                         ctx))

        (local scroll-view
             ((ScrollView {:child (fn [_] icon-grid)
                           :scroll-offset 0}) ctx))

        ;; Layout assembly
    (local top-bar
         ((Flex {:axis :x
                 :children [(FlexChild (fn [_] search-input) 1)
                            (FlexChild (fn [_] theme-combo) 0)]
                 :xspacing 1.0})
          ctx))

    (local sidebar-content
         ((Flex {:axis :y
                 :xalign :stretch
                 :children [(FlexChild (fn [_]
                                          ((Padding {:edge-insets [1.0 1.0]
                                                     :child (fn [c]
                                                               ((Text {:text "Contexts"
                                                                       :style (TextStyle {:scale 1.4
                                                                                          :color (glm.vec4 0.7 0.7 0.7 1)})})
                                                                c))})
                                           ctx))
                                      0)
                            (FlexChild (fn [_] context-scroll-view) 1)]
                 :yspacing 0.5})
          ctx))

    (local content-area
         ((Padding {:edge-insets [1.0 1.0]
                    :child (fn [c]
                             ((Flex {:axis :x
                                     :yalign :stretch
                                     :children [(FlexChild (fn [_] sidebar-content) 1)
                                                (FlexChild (fn [_] scroll-view) 3)]
                                     :xspacing 1.0})
                              c))})
          ctx))

    (local root
         ((Flex {:axis :y
                 :children [(FlexChild (fn [_] ((Padding {:edge-insets [1.0 1.0]
                                                          :child (fn [c] top-bar)})
                                                ctx)) 0)
                            (FlexChild (fn [_] content-area) 1)]
                 :yspacing 1.0})
          ctx))
         
        (set search-listener
             (search-input.model.changed:connect
               (fn [text]
                   (local next-text (or text ""))
                   (set state.search-query next-text)
                   (if (= next-text "")
                       (when (not state.selected-context)
                           (set state.selected-context (or state.last-context default-context))))
                   (if (not (= next-text ""))
                       (set state.selected-context nil))
                   (update-view))))

        (set theme-listener
             (theme-combo.changed:connect
               (fn [val]
                   (set state.selected-theme val)
                   (update-view))))

        ;; Force rebuild once to init
        (update-view)

        (local browser {:layout root.layout})
        (set browser.drop
             (fn [_self]
                 (when (and search-input search-input.model search-listener)
                     (search-input.model.changed:disconnect search-listener true)
                     (set search-listener nil))
                 (when (and theme-combo theme-listener)
                     (theme-combo.changed:disconnect theme-listener true)
                     (set theme-listener nil))
                 (root:drop)))
        browser))

{:XdgIconBrowser XdgIconBrowser}

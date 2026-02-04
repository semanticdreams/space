(local glm (require :glm))
(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))
(local Signal (require :signal))
(local {: Layout} (require :layout))
(local {: resolve-button-colors} (require :widget-theme-utils))

(fn normalize-item [item]
  (assert item "TabView item is required")
  (local kind (type item))
  (if (= kind :table)
      (do
        (local label (or (. item :label) (. item :name) (. item 1)))
        (local builder (or (. item :builder) (. item :child) (. item 2)))
        (assert (or (= (type label) :string)
                    (= (type label) :number))
                "TabView item label must be a string/number")
        (assert (= (type builder) :function)
                "TabView item builder must be a function (widget constructor)")
        {:label (tostring label)
         :builder builder
         :id (or (. item :id) (. item :key) label)})
      (error "TabView items must be tables like {:label \"...\" :builder <fn>} or [\"...\" <fn>]")))

(fn normalize-items [items]
  (local result [])
  (each [_ item (ipairs (or items []))]
    (table.insert result (normalize-item item)))
  result)

(fn clamp [value min-value max-value]
  (math.max min-value (math.min max-value value)))

(fn normalize-index [idx count]
  (local total (math.max 0 (or count 0)))
  (if (<= total 0)
      nil
      (do
        (local raw (or idx 0))
        (local value
          (if (= raw 0)
              1
              (if (< raw 0)
                  (+ total raw 1)
                  raw)))
        (local rounded (math.floor value))
        (clamp rounded 1 total))))

(fn TabView [opts]
  (local options (or opts {}))
  (local items (normalize-items options.items))
  (local horizontal?
    (if (= options.horizontal? nil)
        true
        (not (not options.horizontal?))))
  (local initial-index (or options.initial-tab options.initial-index 0))
  (local tab-spacing (or options.tab-spacing 0.1))
  (local content-spacing (or options.content-spacing 0.1))
  (local active-variant (or options.active-variant :solid))
  (local inactive-variant (or options.inactive-variant :ghost))
  (local tab-padding (or options.tab-padding [0.45 0.3]))
  (local focus-scope-name (or options.focus-scope-name "tab-view"))

  (fn build [ctx]
    (local focus (and ctx ctx.focus))
    (local tab-scope (and focus (focus:create-scope {:name focus-scope-name})))
    (local scoped-focus
      (and focus tab-scope
           (setmetatable {:manager focus.manager
                          :scope tab-scope}
                         {:__index focus})))
    (local tab-ctx
      (if scoped-focus
          (do
            (local child {})
            (each [k v (pairs ctx)]
              (set (. child k) v))
            (set child.focus scoped-focus)
            child)
          ctx))

    (local view {:items items
                 :buttons []
                 :button-row nil
                 :current-tab nil
                 :current-tab-index nil
                 :layout nil
                 :changed (Signal)
                 :focus-scope tab-scope})

    (fn wrap-static [widget]
      (fn [_ctx] widget))

    (fn apply-button-variant [button variant]
      (local colors (resolve-button-colors ctx {:variant variant}))
      (set button.variant colors.variant)
      (set button.ghost? (= colors.variant :ghost))
      (set button.background-color colors.background)
      (set button.hover-background-color colors.hover)
      (set button.pressed-background-color colors.pressed)
      (set button.foreground-color colors.foreground)
      (set button.focus-outline-color colors.focus-outline)
      (when (and button.text button.text.style)
        (set button.text.style.color colors.foreground))
      (when button.update-background-color
        (button:update-background-color {:mark-layout-dirty? false}))
      (when button.update-focus-visual
        (button:update-focus-visual {:mark-layout-dirty? false}))
      (when button.layout
        (button.layout:mark-layout-dirty)))

    (fn update-button-states [self]
      (each [i button (ipairs self.buttons)]
        (apply-button-variant button
                              (if (= i self.current-tab-index)
                                  active-variant
                                  inactive-variant))))

    (fn make-tab-button [index item]
      (Button {:text item.label
               :variant inactive-variant
               :padding tab-padding
               :focus-name (.. "tab-" item.label)
               :on-click (fn [_button _event]
                           (view:set-current-tab index))}))

    (set view.buttons
         (icollect [i item (ipairs items)]
           ((make-tab-button i item) tab-ctx)))

    (local button-children
      (icollect [_ button (ipairs view.buttons)]
        (FlexChild (wrap-static button) 0)))
    (local button-row-builder
      (Flex {:axis (if horizontal? :x :y)
             :reverse (if horizontal? false true)
             :xspacing (if horizontal? tab-spacing 0.0)
             :yspacing (if horizontal? 0.0 tab-spacing)
             :xalign (if horizontal? :start :largest)
             :yalign (if horizontal? :largest :start)
             :children button-children}))
    (local button-row (button-row-builder tab-ctx))
    (set view.button-row button-row)

    (local axis (if horizontal? 2 1))
    (local reverse
      (if (not (= options.reverse nil))
          (not (not options.reverse))
          (if (= axis 2) true false)))

    (fn measurer [self]
      (button-row.layout:measurer)
      (local header-measure button-row.layout.measure)
      (local content-layout (and view.current-tab view.current-tab.layout))
      (when content-layout
        (content-layout:measurer))
      (if (not content-layout)
          (set self.measure header-measure)
          (do
            (local content-measure content-layout.measure)
            (if (= axis 2)
                (set self.measure
                     (glm.vec3 (math.max header-measure.x content-measure.x)
                               (+ header-measure.y content-spacing content-measure.y)
                               (math.max header-measure.z content-measure.z)))
                (set self.measure
                     (glm.vec3 (+ header-measure.x content-spacing content-measure.x)
                               (math.max header-measure.y content-measure.y)
                               (math.max header-measure.z content-measure.z)))))))

    (fn layouter [self]
      (local header-layout button-row.layout)
      (local content-layout (and view.current-tab view.current-tab.layout))
      (local rotation self.rotation)
      (local position self.position)
      (local size self.size)
      (local depth-index (or self.depth-offset-index 0))
      (local clip self.clip-region)

      (local header-size (glm.vec3 size.x size.y size.z))
      (local header-measure header-layout.measure)
      (set (. header-size axis) (math.min (. size axis) (. header-measure axis)))

      (local remaining (- (. size axis) (. header-size axis) content-spacing))
      (local content-axis-size (math.max 0 remaining))
      (local content-size (glm.vec3 size.x size.y size.z))
      (when content-layout
        (set (. content-size axis) content-axis-size))

      (fn axis-offset [offset]
        (do
          (local vec (glm.vec3 0 0 0))
          (set (. vec axis) offset)
          vec))

      (local header-offset
        (if reverse
            (- (. size axis) (. header-size axis))
            0))
      (local content-offset
        (if content-layout
            (if reverse
                0
                (+ (. header-size axis) content-spacing))
            0))

      (set header-layout.size header-size)
      (set header-layout.position (+ position (rotation:rotate (axis-offset header-offset))))
      (set header-layout.rotation rotation)
      (set header-layout.depth-offset-index (+ depth-index 1))
      (set header-layout.clip-region clip)
      (header-layout:layouter)

      (when content-layout
        (set content-layout.size content-size)
        (set content-layout.position (+ position (rotation:rotate (axis-offset content-offset))))
        (set content-layout.rotation rotation)
        (set content-layout.depth-offset-index (+ depth-index 2))
        (set content-layout.clip-region clip)
        (content-layout:layouter)))

    (local layout
      (Layout {:name "tab-view"
               :measurer measurer
               :layouter layouter
               :children [button-row.layout]}))

    (fn emit-change [self prev-index]
      (when options.on-change
        (options.on-change self {:index self.current-tab-index
                                 :previous-index prev-index
                                 :item (and self.current-tab-index (. self.items self.current-tab-index))}))
      (self.changed:emit self.current-tab-index))

    (fn set-current-tab [self idx]
      (local count (length self.items))
      (local next-index (normalize-index idx count))
      (when next-index
        (local prev-index self.current-tab-index)
        (when (not (= prev-index next-index))
          (when self.current-tab
            (layout:set-children [button-row.layout])
            (self.current-tab:drop)
            (set self.current-tab nil))
          (set self.current-tab-index next-index)
          (local item (. self.items next-index))
          (assert item "TabView missing item for requested tab")
          (set self.current-tab (item.builder tab-ctx))
          (layout:set-children [button-row.layout self.current-tab.layout])
          (layout:mark-measure-dirty)
          (self:update-button-states)
          (self:emit-change prev-index))))

    (fn reload-current-tab [self]
      (when self.current-tab-index
        (local idx self.current-tab-index)
        (when self.current-tab
          (layout:set-children [button-row.layout])
          (self.current-tab:drop)
          (set self.current-tab nil))
        (local item (. self.items idx))
        (assert item "TabView missing item for reload")
        (set self.current-tab (item.builder tab-ctx))
        (layout:set-children [button-row.layout self.current-tab.layout])
        (layout:mark-measure-dirty)
        (self:update-button-states)))

    (fn drop [self]
      (when self.current-tab
        (self.current-tab:drop)
        (set self.current-tab nil))
      (when self.button-row
        (self.button-row:drop))
      (when self.focus-scope
        (self.focus-scope:drop)
        (set self.focus-scope nil))
      (self.changed:clear)
      (when self.layout
        (self.layout:drop)))

    (set view.layout layout)
    (set view.set-current-tab set-current-tab)
    (set view.reload-current-tab reload-current-tab)
    (set view.update-button-states update-button-states)
    (set view.emit-change emit-change)
    (set view.drop drop)

    (when (> (length items) 0)
      (view:set-current-tab initial-index))
    view))

TabView

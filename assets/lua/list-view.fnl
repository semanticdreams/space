(local glm (require :glm))
(local {: Layout} (require :layout))
(local ScrollView (require :scroll-view))
(local Padding (require :padding))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Pagination (require :pagination))

(fn copy-items [items]
  (local copy [])
  (each [_ value (ipairs (or items []))]
    (table.insert copy value))
  copy)

(fn ensure-widget [value context]
  (assert (and value value.layout)
          (.. "ListView " context " builder must return a widget with a layout"))
  value)

(fn ListView [opts]
  (local options (or opts {}))
  (local list-name (or options.name "list-view"))

  (fn build [ctx]
    (local list {:context ctx
                 :items (copy-items options.items)
                 :item-spacing (math.max 0 (or options.item-spacing 0.3))
                 :fill-width? (if (not (= options.fill-width nil))
                                  options.fill-width
                                  true)
                 :reverse? (if (not (= options.reverse nil))
                                 options.reverse
                                 true)
                 :title (or options.title options.name "List")
                 :show-header? (if (not (= options.show-head nil))
                                     options.show-head
                                     (not (= (or options.title options.name) nil)))
                 :paginate? (if (not (= options.paginate nil))
                                 options.paginate
                                 false)
                 :items-per-page (math.max 1
                                         (or options.items-per-page
                                             options.num-per-page
                                             options.per-page
                                             10))
                 :scroll-items-per-page nil
                 :auto-scroll-viewport? false
                 :scroll? (if (not (= options.scroll nil))
                              options.scroll
                              true)
                 :scrollbar-width (math.max 0 (or options.scrollbar-width 0.85))
                 :scrollbar-policy (or options.scrollbar-policy :as-needed)
                 :pagination nil
                 :scroll-view nil
                 :pagination-range {:start-index 0 :stop-index 0}
                 :ready? false})

    (local focus-context (and ctx ctx.focus))
    (local focus-manager (and focus-context focus-context.manager))
    (local focus-scope
      (and focus-context
           (focus-context:create-scope {:name (.. list-name "-scope")})))
    (local parking-node
      (and focus-context focus-scope
           (focus-context:create-node {:name (.. list-name "-parking")
                                       :parent focus-scope
                                       :skip-traversal? true})))
    (set list.focus-context focus-context)
    (set list.focus-manager focus-manager)
    (set list.focus-scope focus-scope)
    (set list.parking-node parking-node)

    (set list.pagination-range {:start-index 0 :stop-index (length list.items)})

    (set list.builder
         (or options.builder
             (fn [value child-ctx]
               ((Padding {:edge-insets [0.45 0.35]
                          :child (Text {:text (tostring value)})})
                child-ctx))))

    (when (and options.scroll-items-per-page (> options.scroll-items-per-page 0))
      (set list.scroll-items-per-page (math.max 1 options.scroll-items-per-page)))

    (when list.paginate?
      (set list.scroll? false))

    (when (not list.scroll?)
      (set list.scroll-items-per-page nil))

    (set list.auto-scroll-viewport? (and list.scroll?
                                         list.scroll-items-per-page
                                         (= options.viewport-height nil)))

    (local layout nil)

    (fn measure-layout [self]
      (var width 0)
      (var height 0)
      (var depth 0)
      (local spacing list.item-spacing)
      (local child-count (length self.children))
      (each [idx child (ipairs self.children)]
        (child:measurer)
        (when (> child.measure.x width)
          (set width child.measure.x))
        (when (> child.measure.z depth)
          (set depth child.measure.z))
        (set height (+ height child.measure.y))
        (when (< idx child-count)
          (set height (+ height spacing))))
      (set self.measure (glm.vec3 width height depth)))

    (fn layout-children [self]
      (local spacing list.item-spacing)
      (var offset 0)
      (local child-count (length self.children))
      (each [idx child (ipairs self.children)]
        (local width (if (and list.fill-width? (> self.size.x 0))
                         self.size.x
                         child.measure.x))
        (local height child.measure.y)
        (local depth (math.max child.measure.z self.size.z))
        (set child.size (glm.vec3 width height depth))
        (local child-position (glm.vec3 0 0 0))
        (if list.reverse?
            (set child-position.y (- self.size.y offset height)))
        (if (not list.reverse?)
            (set child-position.y offset))
        (set child.position (+ self.position (self.rotation:rotate child-position)))
        (set child.rotation self.rotation)
        (set child.depth-offset-index self.depth-offset-index)
        (set child.clip-region self.clip-region)
        (child:layouter)
        (set offset (+ offset height))
        (when (< idx child-count)
          (set offset (+ offset spacing)))))

    (local layout
      (Layout {:name list-name
               :measurer measure-layout
               :layouter layout-children}))

    (set list.content-layout layout)
    (when (and focus-context parking-node)
      (focus-context:attach-bounds parking-node {:layout layout}))
    (set list.header nil)
    (set list.item-widgets [])
    (set list.header-focus-nodes [])
    (set list.item-focus-nodes [])
    (set list.pagination-focus-nodes [])

    (fn with-list-scope [self f]
      (if (and self.focus-context self.focus-scope self.focus-context.get-scope)
          (do
            (local original (self.focus-context:get-scope))
            (self.focus-context:set-scope self.focus-scope)
            (local result (f))
            (self.focus-context:set-scope original)
            result)
          (f)))
    (set list.with-list-scope with-list-scope)

    (fn capture-focus-nodes [self f]
      (if (and self.focus-context self.focus-context.capture)
          (do
            (local (result nodes) (self.focus-context:capture f))
            (values result (or nodes [])))
          (values (f) [])))
    (set list.capture-focus-nodes capture-focus-nodes)

    (fn node-in-scope? [node scope]
      (var current node)
      (var found false)
      (while (and current (not found))
        (when (= current scope)
          (set found true))
        (set current current.parent))
      found)

    (fn park-focus [self]
      (when (and self.focus-manager self.parking-node self.focus-scope)
        (local current (self.focus-manager:get-focused-node))
        (when (and current (node-in-scope? current self.focus-scope))
          (when (not (= current self.parking-node))
            (self.parking-node:request-focus)))))

    (fn find-first-focusable [self]
      (if (not (and self.focus-manager self.focus-scope))
          nil
          (do
            (local candidates
              (if self.focus-manager._get-focusables-in-scope
                  (self.focus-manager:_get-focusables-in-scope self.focus-scope)
                  []))
            (var idx 1)
            (var chosen nil)
            (while (and (<= idx (length candidates)) (not chosen))
              (local candidate (. candidates idx))
              (when (and candidate (not (= candidate self.parking-node)))
                (if (or (not self.focus-manager._can-traverse)
                        (self.focus-manager:_can-traverse candidate))
                    (set chosen candidate)))
              (set idx (+ idx 1)))
            chosen)))

    (fn restore-focus [self]
      (if (not (and self.focus-manager self.parking-node self.focus-scope))
          nil
          (do
            (local current (self.focus-manager:get-focused-node))
            (if (not (= current self.parking-node))
                nil
                (do
                  (local target (find-first-focusable self))
                  (when target
                    (target:request-focus)))))))

    (set list.restore-focus restore-focus)

    (fn append-focus-nodes [acc nodes]
      (each [_ node (ipairs (or nodes []))]
        (when node
          (table.insert acc node))))

    (fn reorder-focus-nodes [self]
      (when (and self.focus-context self.focus-scope self.focus-context.attach-at)
        (local ordered [])
        (when self.parking-node
          (table.insert ordered self.parking-node))
        (append-focus-nodes ordered self.header-focus-nodes)
        (each [_ nodes (ipairs self.item-focus-nodes)]
          (append-focus-nodes ordered nodes))
        (append-focus-nodes ordered self.pagination-focus-nodes)
        (var index 1)
        (each [_ node (ipairs ordered)]
          (when (and node (= node.parent self.focus-scope))
            (self.focus-context:attach-at node self.focus-scope index)
            (set index (+ index 1))))))
    (set list.reorder-focus-nodes reorder-focus-nodes)

    (fn drop-items [self]
      (park-focus self)
      (each [_ widget (ipairs self.item-widgets)]
        (widget:drop))
      (set self.item-widgets [])
      (set self.item-focus-nodes []))

    (fn drop-header [self]
      (park-focus self)
      (when self.header
        (self.header:drop)
        (set self.header nil))
      (set self.header-focus-nodes []))

    (local resolve-header-title-color
      (fn [context]
        (local theme (and context context.theme))
        (if (not theme)
            nil
            (do
              (local list-view-theme theme.list-view)
              (local header-theme (and list-view-theme list-view-theme.header))
              (local text-theme theme.text)
              (or (and header-theme header-theme.foreground)
                  (and header-theme header-theme.color)
                  (and text-theme text-theme.header)
                  (and text-theme text-theme.title)
                  (and text-theme text-theme.foreground)
                  (and text-theme text-theme.color))))))

    (fn rebuild-header [self]
      (self:drop-header)
      (when self.show-header?
        (local header-builder
          (or options.header-builder
              (fn [header-ctx]
                (local title-color
                  (or (resolve-header-title-color header-ctx)
                      (glm.vec4 1 0 0 1)))
                ((Padding {:edge-insets [0.5 0.35]
                           :child (Text {:text self.title
                                         :style (TextStyle {:color title-color
                                                            :weight :bold})})})
                 header-ctx))))
        (local (header nodes)
          (self:capture-focus-nodes
            (fn []
              (self:with-list-scope
                (fn []
                  (ensure-widget (header-builder self.context) "header"))))))
        (set self.header header)
        (set self.header-focus-nodes nodes)))

    (fn get-visible-range [self]
      (if (and self.paginate? self.pagination-range)
          self.pagination-range
          {:start-index 0 :stop-index (length self.items)}))

    (fn rebuild-items [self]
      (self:drop-items)
      (set self.item-focus-nodes [])
      (local range (self:get-visible-range))
      (local start-index (math.max 0 (or range.start-index 0)))
      (local stop-index (math.max start-index
                                  (math.min (or range.stop-index (length self.items))
                                            (length self.items))))
      (var idx (+ start-index 1))
      (while (<= idx stop-index)
        (local item (. self.items idx))
        (local (built nodes)
          (self:capture-focus-nodes
            (fn []
              (self:with-list-scope
                (fn []
                  (ensure-widget (self.builder item self.context) "item"))))))
        (table.insert self.item-widgets built)
        (table.insert self.item-focus-nodes nodes)
        (set idx (+ idx 1)))
      (self:reorder-focus-nodes)
      (self:restore-focus))

    (fn update-layout-children [self]
      (local new-children [])
      (when self.header
        (table.insert new-children self.header.layout))
      (each [_ widget (ipairs self.item-widgets)]
        (table.insert new-children widget.layout))
      (when (and self.paginate? self.pagination)
        (table.insert new-children self.pagination.layout))
      (self.content-layout:set-children new-children)
      (self.content-layout:mark-measure-dirty)
      (self.content-layout:mark-layout-dirty)
      (self:update-scroll-viewport))

    (fn compute-scroll-viewport-height [self]
      (if (not (and self.scroll?
                    self.scroll-view
                    self.auto-scroll-viewport?
                    self.scroll-items-per-page
                    (> self.scroll-items-per-page 0)))
          nil
          (do
            (self.content-layout:measurer)
            (local spacing (or self.item-spacing 0))
            (local limit (math.min self.scroll-items-per-page (length self.item-widgets)))
            (var height 0)
            (var added 0)
            (fn add-height [value]
              (local amount (or value 0))
              (when (> amount 0)
                (when (> added 0)
                  (set height (+ height spacing)))
                (set height (+ height amount))
                (set added (+ added 1))))
            (when (and self.header self.header.layout)
              (add-height (or self.header.layout.measure.y 0)))
            (for [idx 1 limit]
              (local widget (. self.item-widgets idx))
              (when (and widget widget.layout)
                (add-height (or widget.layout.measure.y 0))))
            height)))

    (fn update-scroll-viewport [self]
      (when (and self.scroll-view self.scroll-view.set-viewport-height self.auto-scroll-viewport?)
        (local height (self:compute-scroll-viewport-height))
        (when height
          (self.scroll-view:set-viewport-height height))))

    (fn on-pagination-changed [self data]
      (set self.pagination-range {:start-index (math.max 0 (or data.start-index 0))
                                  :stop-index (math.max 0 (or data.stop-index 0))})
      (when self.ready?
        (self:rebuild-items)
        (self:update-layout-children)))

    (fn ensure-pagination [self]
      (if (not self.paginate?)
          (do
            (when self.pagination
              (self.pagination:drop)
              (set self.pagination nil))
            (set self.pagination-focus-nodes [])
            (set self.pagination-range {:start-index 0
                                        :stop-index (length self.items)}))
          (do
            (when (not self.pagination)
              (local pagination-builder
                (Pagination {:items-per-page self.items-per-page
                             :num-items (length self.items)
                             :on-page-change (fn [_pagination data]
                                               (self:on-pagination-changed data))}))
              (local (pagination-widget nodes)
                (self:capture-focus-nodes
                  (fn []
                    (ensure-widget (pagination-builder self.context)
                                   "pagination"))))
              (set self.pagination pagination-widget)
              (set self.pagination-focus-nodes nodes))
            (when self.pagination
              (self.pagination:set-num-items (length self.items))))))

    (fn rebuild-items-only [self]
      (self:rebuild-items)
      (self:update-layout-children))

    (fn rebuild-children [self]
      (set self.ready? false)
      (self:ensure-pagination)
      (self:rebuild-header)
      (self:rebuild-items)
      (self:update-layout-children)
      (set self.ready? true))

    (fn reset-scroll-position [self]
      (when (and self.scroll-view self.scroll-view.reset-scroll-position)
        (self.scroll-view:reset-scroll-position)))

    (fn set-items [self new-items]
      (set self.items (copy-items new-items))
      (if (and self.paginate? self.pagination)
          (do
            (self.pagination:set-num-items (length self.items))
            (self.pagination:set-page 0 true))
          (self:rebuild-children))
      (self:reset-scroll-position)
      (self:update-scroll-viewport))

    (fn update-item [self index item]
      (local idx (or index 0))
      (when (and (> idx 0) (<= idx (length self.items)))
        (set (. self.items idx) item)
        (local range (self:get-visible-range))
        (local start-index (math.max 0 (or range.start-index 0)))
        (local stop-index (math.max start-index
                                    (math.min (or range.stop-index (length self.items))
                                              (length self.items))))
        (local in-range (and (>= idx (+ start-index 1)) (<= idx stop-index)))
        (when in-range
          (local widget-index (- idx start-index))
          (local (built nodes)
            (self:capture-focus-nodes
              (fn []
                (self:with-list-scope
                  (fn []
                    (ensure-widget (self.builder item self.context) "item"))))))
          (local current (. self.item-widgets widget-index))
          (when current
            (current:drop))
          (set (. self.item-widgets widget-index) built)
          (set (. self.item-focus-nodes widget-index) nodes)
          (self:update-layout-children)
          (self:reorder-focus-nodes))))

    (fn set-builder [self new-builder]
      (when new-builder
        (set self.builder new-builder)
        (self:rebuild-children)))

    (fn set-title [self new-title]
      (set self.title (or new-title self.title))
      (when self.show-header?
        (self:rebuild-children)))

    (fn drop-content [self]
      (self:drop-header)
      (self:drop-items)
      (when self.pagination
        (self.pagination:drop)
        (set self.pagination nil))
      (set self.pagination-focus-nodes [])
      (when self.content-layout
        (self.content-layout:set-children [])
        (self.content-layout:drop)
        (set self.content-layout nil)))

    (fn drop [self]
      (if (and self.scroll-view self.scroll?)
          (do
            (self.scroll-view:drop)
            (set self.scroll-view nil))
          (drop-content self))
      (when self.parking-node
        (self.parking-node:drop)
        (set self.parking-node nil))
      (when self.focus-scope
        (self.focus-scope:drop)
        (set self.focus-scope nil)))

    (set list.drop-header drop-header)
    (set list.drop-items drop-items)
    (set list.rebuild-header rebuild-header)
    (set list.rebuild-items rebuild-items)
    (set list.get-visible-range get-visible-range)
    (set list.update-layout-children update-layout-children)
    (set list.ensure-pagination ensure-pagination)
    (set list.rebuild-items-only rebuild-items-only)
    (set list.on-pagination-changed on-pagination-changed)
    (set list.rebuild-children rebuild-children)
    (set list.reset-scroll-position reset-scroll-position)
    (set list.set-items set-items)
    (set list.update-item update-item)
    (set list.set-builder set-builder)
    (set list.set-title set-title)
    (set list.compute-scroll-viewport-height compute-scroll-viewport-height)
    (set list.update-scroll-viewport update-scroll-viewport)
    (set list.drop-content drop-content)
    (set list.drop drop)

    (when list.scroll?
      (local child {:layout layout})
      (set child.drop (fn [_child]
                        (drop-content list)))
      (local scroll-view-builder
        (ScrollView {:child (fn [_ctx] child)
                     :name (.. list-name "-scroll-view")
                     :scrollbar-width list.scrollbar-width
                     :scrollbar-policy list.scrollbar-policy
                     :viewport-height options.viewport-height}))
      (local scroll-view (scroll-view-builder ctx))
      (set list.scroll-view scroll-view)
      (set list.layout scroll-view.layout))
    (when (not list.scroll?)
      (set list.layout list.content-layout))

    (fn set-scroll-offset [self offset]
      (when (and self.scroll-view self.scroll-view.set-scroll-offset)
        (self.scroll-view:set-scroll-offset offset)))

    (fn get-scroll-offset [self]
      (if (and self.scroll-view self.scroll-view.get-scroll-offset)
          (self.scroll-view:get-scroll-offset)
          0))

    (fn set-viewport-height [self height]
      (when (and self.scroll-view self.scroll-view.set-viewport-height)
        (self.scroll-view:set-viewport-height height)))

    (set list.set-scroll-offset set-scroll-offset)
    (set list.get-scroll-offset get-scroll-offset)
    (set list.set-viewport-height set-viewport-height)

    (list:rebuild-children)
    list))

ListView

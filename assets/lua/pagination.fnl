(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Padding (require :padding))
(local Text (require :text))
(local {: Layout} (require :layout))

(fn make-spacer []
  (fn build [_ctx]
    (local layout
      (Layout {:name "pagination-spacer"
               :measurer (fn [self]
                           (set self.measure (glm.vec3 0 0 0)))
               :layouter (fn [_self] nil)}))
    (fn drop [self]
      (self.layout:drop))
    {:layout layout :drop drop}))

(fn clamp [value min-value max-value]
  (math.max min-value (math.min max-value value)))

(fn Pagination [opts]
  (local options (or opts {}))
  (local per-page (math.max 1 (or options.items-per-page
                                  options.num-per-page
                                  options.per-page
                                  10)))
  (fn build [ctx]
    (local pagination {:context ctx
                       :items-per-page per-page
                       :num-items (math.max 0 (or options.num-items 0))
                       :current-page 0
                       :on-page-change options.on-page-change
                       :ready? false})

    (fn icons-available? []
      (and ctx ctx.icons))

    (fn make-button [icon-name fallback-text handler]
      (local button-opts {:on-click handler
                          :variant (or options.button-variant :ghost)
                          :padding (or options.button-padding [0.35 0.35])})
      (if (and icon-name (icons-available?))
          (set button-opts.icon icon-name)
          (set button-opts.text fallback-text))
      (Button button-opts))

    (local page-label-builder (Padding {:edge-insets [0.25 0.15]
                                        :child (Text {:text "Page 1 / 1"})}))
    (local items-label-builder (Padding {:edge-insets [0.25 0.15]
                                         :child (Text {:text "Items 0 / 0"})}))

    (local spacer-builder (make-spacer))
    (local first-button-builder
      (make-button "first_page" "<<"
                   (fn [_button _event]
                     (pagination:set-page 0))))
    (local prev-button-builder
      (make-button "chevron_left" "<"
                   (fn [_button _event]
                     (pagination:set-page (- pagination.current-page 1)))))
    (local next-button-builder
      (make-button "chevron_right" ">"
                   (fn [_button _event]
                     (pagination:set-page (+ pagination.current-page 1)))))
    (local last-button-builder
      (make-button "last_page" ">>"
                   (fn [_button _event]
                     (pagination:set-page math.huge))))

    (fn wrap-static [widget]
      (fn [_ctx] widget))

    (local first-button (first-button-builder ctx))
    (local prev-button (prev-button-builder ctx))
    (local page-label (page-label-builder ctx))
    (local spacer (spacer-builder ctx))
    (local items-label (items-label-builder ctx))
    (local next-button (next-button-builder ctx))
    (local last-button (last-button-builder ctx))

    (local row-builder
      (Flex {:axis 1
             :xspacing (or options.xspacing 0.3)
             :yalign :center
             :children
             [(FlexChild (wrap-static first-button) 0)
              (FlexChild (wrap-static prev-button) 0)
              (FlexChild (wrap-static page-label) 0)
              (FlexChild (wrap-static spacer) 1)
              (FlexChild (wrap-static items-label) 0)
              (FlexChild (wrap-static next-button) 0)
              (FlexChild (wrap-static last-button) 0)]}))
    (local row (row-builder ctx))

    (fn last-page [self]
      (if (<= self.num-items 0)
          0
          (math.max 0
                    (- (math.ceil (/ self.num-items self.items-per-page)) 1))))

    (fn compute-range [self]
      (local start (* self.current-page self.items-per-page))
      (local stop (math.min self.num-items (+ start self.items-per-page)))
      {:start-index start :stop-index stop})

    (fn update-labels [self]
      (var total-pages (+ (self:last-page) 1))
      (when (= self.num-items 0)
        (set total-pages 1))
      (local range (self:compute-range))
      (local start-display (if (> self.num-items 0)
                               (+ range.start-index 1)
                               0))
      (local stop-display (if (> self.num-items 0)
                              (math.max start-display range.stop-index)
                              0))
      (page-label.child:set-text
        (string.format "Page %d / %d" (+ self.current-page 1) total-pages))
      (if (> self.num-items 0)
          (items-label.child:set-text
            (string.format "%d-%d of %d"
                           start-display
                           (math.max start-display stop-display)
                           self.num-items))
          (items-label.child:set-text "Items 0 / 0")))

    (fn emit-change [self]
      (local range (self:compute-range))
      (when self.on-page-change
        (self.on-page-change self {:page self.current-page
                                   :start-index range.start-index
                                   :stop-index range.stop-index})))

    (fn clamp-page [self page]
      (local last (self:last-page))
      (clamp (or page 0) 0 last))

    (fn set-page [self page force?]
      (local next (self:clamp-page page))
      (when (or force? (not (= next self.current-page)))
        (set self.current-page next)
        (self:update-labels)
        (self:emit-change)))

    (fn set-num-items [self count]
      (set self.num-items (math.max 0 (or count 0)))
      (self:set-page self.current-page true))

    (fn drop [self]
      (self.row:drop))

    (set pagination.layout row.layout)
    (set pagination.row row)
    (set pagination.page-label page-label.child)
    (set pagination.items-label items-label.child)
    (set pagination.first-button first-button)
    (set pagination.prev-button prev-button)
    (set pagination.next-button next-button)
    (set pagination.last-button last-button)
    (set pagination.spacer spacer)
    (set pagination.last-page last-page)
    (set pagination.compute-range compute-range)
    (set pagination.update-labels update-labels)
    (set pagination.emit-change emit-change)
    (set pagination.clamp-page clamp-page)
    (set pagination.set-page set-page)
    (set pagination.set-num-items set-num-items)
    (set pagination.drop drop)

    (pagination:update-labels)
    (pagination:set-page pagination.current-page true)

    pagination)
  build)

Pagination

(local glm (require :glm))
(local {: Layout} (require :layout))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))

(fn static-builder [element]
  (fn [_ctx] element))

(fn WorldTabsWidget [opts]
  (local options (or opts {}))
  (local world-manager (assert options.world-manager "WorldTabsWidget requires :world-manager"))
  (local tab-spacing (or options.tab-spacing 0.1))
  (local get-menu-manager
    (or options.get-menu-manager
        (fn []
          (or options.menu-manager app.menu-manager))))

  (fn build [ctx]
    (var row nil)
    (var world-listener nil)
    (local self {:layout nil})

    (fn resolve-tab-index-by-id [id]
      (var resolved nil)
      (each [_ candidate (ipairs (world-manager:list-tabs))]
        (when (and (not resolved) (= candidate.id id))
          (set resolved candidate.index)))
      resolved)

    (fn open-tab-menu [tab event]
      (local menu-manager (get-menu-manager))
      (assert menu-manager "WorldTabsWidget tab context menu requires menu manager")
      (assert (and event event.point) "WorldTabsWidget tab context menu requires event.point")
      (menu-manager:open {:position event.point
                          :open-button (and event event.button)
                          :actions [{:name "Delete world"
                                     :on-click (fn [_button _click-event]
                                                 (local idx (resolve-tab-index-by-id tab.id))
                                                 (when idx
                                                   (world-manager:close-world-index idx)))}]}))

    (fn create-tab-button [tab]
      (Button {:text tab.name
               :variant (if tab.active? :primary :ghost)
               :on-click (fn [_button _event]
                           (world-manager:activate-index tab.index))
               :on-right-click (fn [_button event]
                                 (open-tab-menu tab event))}))

    (fn create-add-button []
      (Button {:text "+"
               :variant :primary
               :on-click (fn [_button _event]
                           (world-manager:create-home-world {:activate? true}))}))

    (fn build-row []
      (local tabs (world-manager:list-tabs))
      (local children
        (icollect [_ tab (ipairs tabs)]
          (FlexChild (static-builder ((create-tab-button tab) ctx)))))
      (table.insert children (FlexChild (static-builder ((create-add-button) ctx))))
      ((Flex {:axis 1
              :xspacing tab-spacing
              :yalign :center
              :children children}) ctx))

    (fn rebuild []
      (when row
        (row:drop)
        (set row nil))
      (set row (build-row))
      (self.layout:set-children [row.layout])
      (self.layout:mark-measure-dirty))

    (fn measurer [layout-self]
      (if row
          (do
            (row.layout:measurer)
            (set layout-self.measure row.layout.measure))
          (set layout-self.measure (glm.vec3 0.001 0.001 0.001))))

    (fn layouter [layout-self]
      (when row
        (set row.layout.size layout-self.size)
        (set row.layout.position layout-self.position)
        (set row.layout.rotation layout-self.rotation)
        (set row.layout.clip-region layout-self.clip-region)
        (set row.layout.depth-offset-index layout-self.depth-offset-index)
        (row.layout:layouter)))

    (local layout
      (Layout {:name "world-tabs-widget"
               :measurer measurer
               :layouter layouter
               :children []}))
    (set self.layout layout)
    (rebuild)
    (set world-listener (world-manager.changed:connect
                          (fn [_event]
                            (rebuild))))

    (fn drop [_self]
      (when world-listener
        (world-manager.changed:disconnect world-listener true)
        (set world-listener nil))
      (when row
        (row:drop)
        (set row nil))
      (layout:drop))

    {:layout layout
     :drop drop}))

WorldTabsWidget

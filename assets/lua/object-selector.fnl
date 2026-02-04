(local glm (require :glm))
(local Signal (require :signal))
(local BoxSelector (require :box-selector))
(local viewport-utils (require :viewport-utils))
(local logging (require :logging))

(fn shallow-copy [items]
    (local copy [])
    (each [_ item (ipairs (or items []))]
        (table.insert copy item))
    copy)

(fn selection-equal? [a b]
    (if (not (= (length a) (length b)))
        false
        (do
            (var match-count 0)
            (each [_ item-a (ipairs a)]
                (each [_ item-b (ipairs b)]
                    (when (= item-a item-b)
                        (set match-count (+ match-count 1)))))
            (= match-count (length a)))))

(fn resolve-position [selectable]
    (or (and selectable selectable.position)
        (and selectable selectable.layout selectable.layout.position)))

(fn replace-contents [target source]
    (for [i (length target) 1 -1]
        (table.remove target i))
    (each [_ item (ipairs (or source []))]
        (table.insert target item)))

(fn default-project [position opts]
    (local options (or opts {}))
    (local viewport (viewport-utils.to-table (or options.viewport app.viewport)))
    (assert viewport "ObjectSelector requires a viewport")
    (assert (> viewport.width 0) "ObjectSelector requires viewport width > 0")
    (assert (> viewport.height 0) "ObjectSelector requires viewport height > 0")
    (local view (or options.view
                    (and app.scene app.scene.get-view-matrix
                         (app.scene:get-view-matrix))
                    (and app.camera app.camera.get-view-matrix
                         (app.camera:get-view-matrix))))
    (assert view "ObjectSelector requires a view matrix")
    (local projection (or options.projection
                           (and app.scene app.scene.projection)
                           app.projection))
    (assert projection "ObjectSelector requires a projection matrix")
    (assert (and glm glm.project) "ObjectSelector requires glm.project")
    (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
    (local projected (glm.project position view projection viewport-vec))
    (assert projected "glm.project returned nil")
    (glm.vec3 projected.x
          (- (+ viewport.height viewport.y) projected.y)
          projected.z))

(fn box->bounds [box]
    (local p1 (or box.p1 (. box 1)))
    (local p2 (or box.p2 (. box 2)))
    (when (and p1 p2)
        (local min-x (math.min p1.x p2.x))
        (local max-x (math.max p1.x p2.x))
        (local min-y (math.min p1.y p2.y))
        (local max-y (math.max p1.y p2.y))
        {:min-x min-x :max-x max-x :min-y min-y :max-y max-y}))

(fn ObjectSelector [opts]
    (local options (or opts {}))
    (local provided-box (or options.box_selector
                            (rawget options "box-selector")
                            (BoxSelector {:ctx options.ctx
                                          :unproject options.unproject
                                          :color options.color})))
    (local box (if (= (type provided-box) :function)
                   (provided-box)
                   provided-box))
    (local project (or options.project default-project))
    (local changed (Signal))
    (local exited (Signal))
    (var selectables [])
    (local selected [])
    (var enabled? (not (= options.enabled? false)))
(fn table-keys [item]
    (local keys [])
    (when (= (type item) :table)
        (each [key _ (pairs item)]
            (table.insert keys (tostring key))))
    (table.sort keys)
    keys)

(fn format-glm-vec3 [v]
    (if (not v)
        "nil"
        (let [x (or v.x (. v 1) 0)
              y (or v.y (. v 2) 0)
              z (or v.z (. v 3) 0)]
            (string.format "(%.3f, %.3f, %.3f)" x y z))))

    (fn format-selectable [item]
        (or (and item item.label)
            (and item item.key)
            (tostring item)))

    (fn format-labels [items]
        (local labels [])
        (each [_ item (ipairs (or items []))]
            (table.insert labels (format-selectable item)))
        (if (> (length labels) 0)
            (table.concat labels ", ")
            "none"))

    (fn log-selection [items]
        (logging.info (string.format "[selection] %s" (format-labels items))))

    (local on-box-changed
      (fn [box-bounds]
        (when enabled?
          (local bounds (box->bounds box-bounds))
          (local projected [])
          (when bounds
            (each [_ selectable (ipairs selectables)]
              (local position (resolve-position selectable))
              (when position
                (local screen (project position options))
                (when (and screen
                           (>= screen.x bounds.min-x)
                           (<= screen.x bounds.max-x)
                           (>= screen.y bounds.min-y)
                           (<= screen.y bounds.max-y))
                  (table.insert projected selectable)))))
          (replace-contents selected projected)
          (log-selection selected)
          (changed:emit selected))))
    (box.changed.connect on-box-changed)
    (box.exited.connect (fn [_] (exited:emit)))

    (fn set-selectables [_self new-selectables]
        (local filtered (shallow-copy new-selectables))
        (replace-contents selectables filtered)
        (local intersection [])
        (each [_ item (ipairs selected)]
            (each [_ candidate (ipairs selectables)]
                (when (= item candidate)
                    (table.insert intersection item))))
        (when (not (selection-equal? selected intersection))
            (replace-contents selected intersection)
            (log-selection selected)
            (changed:emit selected)))

    (fn add-selectables [_self new-selectables]
        (each [_ selectable (ipairs (or new-selectables []))]
            (table.insert selectables selectable)))

    (fn remove-selectables [_self removals]
        (local keep [])
        (each [_ selectable (ipairs selectables)]
            (var removed false)
            (each [_ target (ipairs (or removals []))]
                (when (= selectable target)
                    (set removed true)))
            (when (not removed)
                (table.insert keep selectable)))
        (set selectables keep)
        (local intersection [])
        (each [_ item (ipairs selected)]
            (each [_ candidate (ipairs selectables)]
                (when (= item candidate)
                    (table.insert intersection item))))
        (when (not (selection-equal? selected intersection))
            (replace-contents selected intersection)
            (changed:emit selected)))

    (fn unselect-all [_self]
        (when (> (length selected) 0)
            (replace-contents selected [])
            (log-selection selected)
            (changed:emit selected)))

    (fn set-selected [_self items emit-changed?]
        (local desired (or items []))
        (when (not (selection-equal? selected desired))
            (replace-contents selected desired)
            (when (not (= emit-changed? false))
                (log-selection selected)
                (changed:emit selected))))

    (fn on-mouse-button [self payload]
        (when enabled?
            (box:on-mouse-button payload)))

    (fn on-mouse-motion [self payload]
        (when enabled?
            (box:on-mouse-motion payload)))

    (fn on-key-down [self payload]
        (when enabled?
            (box:on-key-down payload)))

    (fn enable [_self]
        (set enabled? true)
        enabled?)

    (fn disable [self]
        (set enabled? false)
        (self:cancel-selection)
        enabled?)

    (fn toggle [self]
        (if enabled?
            (disable self)
            (enable self)))

    (fn cancel-selection [_self]
        (box:cancel))

    (fn drop [_self]
        (box:drop)
        (changed:clear)
        (exited:clear))

    {:selectables selectables
     :selected selected
     :changed changed
     :exited exited
     :box box
     :enable enable
     :disable disable
     :toggle toggle
     :enabled? (fn [_self] enabled?)
     :active? (fn [_self] (box:active?))
     :set-selectables set-selectables
     :add-selectables add-selectables
     :remove-selectables remove-selectables
     :set-selected set-selected
     :unselect-all unselect-all
     :on-mouse-button on-mouse-button
     :on-mouse-motion on-mouse-motion
     :on-key-down on-key-down
     :cancel-selection cancel-selection
     :drop drop})

ObjectSelector

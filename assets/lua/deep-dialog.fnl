(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local {: Layout} (require :layout))
(local Card (require :card))
(local Button (require :button))
(local Cuboid (require :cuboid))
(local Padding (require :padding))
(local Rectangle (require :rectangle))
(local Sized (require :sized))
(local Text (require :text))
(local {: get-button-theme-colors} (require :widget-theme-utils))

(fn make-flex-spacer []
  (fn build [_ctx]
    (local layout
      (Layout {:name "deep-dialog-flex-spacer"
               :measurer (fn [self]
                           (set self.measure (glm.vec3 0 0 0)))
               :layouter (fn [_self] nil)}))
    (fn drop [self]
      (self.layout:drop))
    {:layout layout :drop drop}))

(fn resolve-action-name [action]
  (or action.name (. action 1)))

(fn resolve-action-handler [action]
  (or action.on-click action.handler action.fn (. action 2)))

(fn normalize-actions [actions]
  (local normalized [])
  (each [_ entry (ipairs (or actions []))]
    (when (not (= (type entry) :table))
      (error "DeepDialog actions must be provided as tables"))
    (local name (resolve-action-name entry))
    (assert name "DeepDialog action is missing a name")
    (table.insert normalized
                  {:name name
                   :handler (resolve-action-handler entry)
                   :variant entry.variant
                   :padding entry.padding
                   :icon (or entry.icon name)}))
  normalized)

(fn resolve-action-variant [options]
  (or options.action-variant :tertiary))

(fn resolve-titlebar-color [ctx options action-variant]
  (or options.titlebar-color
      options.titlebar-background-color
      (do
        (local theme-colors (get-button-theme-colors ctx action-variant))
        (or (and theme-colors theme-colors.background)
            (glm.vec4 0.2 0.2 0.2 1)))))

(fn resolve-body-padding [options]
  (if (= options.body-padding false)
      nil
      (or options.body-padding options.content-padding [0.6 0.6])))

(fn resolve-inset [options]
  (math.max 0 (or options.inset 0.1)))

(fn resolve-dialog-depth [options content-depth]
  (if (not (= options.depth nil))
      (math.max 0 (or options.depth 0))
      (math.max (+ (math.max 0 (or content-depth 0))
                   (* 2 (resolve-inset options)))
                (math.max 0 (or options.min-depth 0)))))

(fn make-action-row [actions options action-variant]
  (local resolved-variant (or action-variant (resolve-action-variant options)))
  (local action-padding (or options.action-padding [0.2 0.2]))
  (Flex
    {:axis 1
     :xspacing (or options.action-spacing 0)
     :yalign :center
     :children
     (icollect [_ action (ipairs actions)]
               (FlexChild
                 (Button {:icon action.icon
                          :variant (or action.variant resolved-variant)
                          :padding (or action.padding action-padding)
                          :focusable? (= action.focusable? true)
                          :on-click (if action.handler
                                      (fn [button event]
                                        (action.handler button event))
                                      nil)})
                 0))}))

(fn build-deep-dialog-cuboid [ctx options runtime-opts]
  (assert options.title "DeepDialog requires :title")
  (assert options.child "DeepDialog requires :child")

  (local actions (normalize-actions options.actions))
  (local title-span
    (Text {:text options.title
           :style options.title-style}))
  (local title
    (Padding {:child title-span
              :edge-insets (or options.title-padding [0.9 0.5])}))
  (local action-variant (resolve-action-variant options))
  (local action-row (make-action-row actions options action-variant))
  (local spacer (make-flex-spacer))
  (local titlebar-children [(FlexChild title 0)])
  (when (> (length actions) 0)
    (table.insert titlebar-children (FlexChild spacer 1))
    (table.insert titlebar-children (FlexChild action-row 0)))
  (local titlebar-content
    (Flex {:axis 1
           :xspacing (or options.titlebar-spacing 0.5)
           :yalign :center
           :children titlebar-children}))
  (local titlebar-color (resolve-titlebar-color ctx options action-variant))
  (local titlebar ((Card {:child titlebar-content :color titlebar-color}) ctx))

  (local body-padding (resolve-body-padding options))
  (local body-builder
    (if body-padding
        (Padding {:edge-insets body-padding
                  :child options.child})
        options.child))
  (local body (body-builder ctx runtime-opts))

  (var titlebar-height 0)
  (var dialog-depth 0)
  (var body-measure-depth 0)

  (local front-layout
    (Layout {:name "deep-dialog-front"
             :children [titlebar.layout]
             :measurer (fn [self]
                         (titlebar.layout:measurer)
                         (body.layout:measurer)
                         (set titlebar-height (or (and titlebar.layout.measure titlebar.layout.measure.y) 0))
                         (local body-width (or (and body.layout.measure body.layout.measure.x) 0))
                         (local body-height (or (and body.layout.measure body.layout.measure.y) 0))
                         (local body-depth (or (and body.layout.measure body.layout.measure.z) 0))
                         (set body-measure-depth body-depth)
                         (local title-width (or (and titlebar.layout.measure titlebar.layout.measure.x) 0))
                         (local title-depth (or (and titlebar.layout.measure titlebar.layout.measure.z) 0))
                         (local width (math.max title-width body-width))
                         (local height (+ titlebar-height body-height))
                         (set dialog-depth
                              (resolve-dialog-depth options (math.max title-depth body-depth)))
                         (set self.measure (glm.vec3 width height dialog-depth)))
             :layouter (fn [self]
                        (set titlebar.layout.size (glm.vec3 self.size.x titlebar-height 0))
                        (set titlebar.layout.position
                             (+ self.position
                                (self.rotation:rotate
                                  (glm.vec3 0 (- self.size.y titlebar-height) 0))))
                        (set titlebar.layout.rotation self.rotation)
                        (set titlebar.layout.depth-offset-index self.depth-offset-index)
                        (set titlebar.layout.clip-region self.clip-region)
                        (titlebar.layout:layouter))}))
  (local drop-front-face
    (fn [_self]
      (front-layout:drop)
      (titlebar:drop)))

  (local build-front-face
    (fn [_ctx]
      {:layout front-layout
       :drop drop-front-face}))

  (local default-side-color (glm.vec4 0.16 0.16 0.16 1))
  (local side-color
    (if options.side-color
        options.side-color
        (do
          (local theme (get-button-theme-colors ctx (or options.variant :tertiary)))
          (or (and theme theme.background) default-side-color))))
  (var x-side-size (glm.vec3 0 0 0))
  (var y-side-size (glm.vec3 0 0 0))

  (fn update-depth [depth]
    (local resolved (math.max 0 (or depth 0)))
    (set x-side-size.x resolved)
    (set x-side-size.y 0)
    (set x-side-size.z 0)
    (set y-side-size.x 0)
    (set y-side-size.y resolved)
    (set y-side-size.z 0))

  (local cuboid-builder
    (Cuboid {:children
             [build-front-face
              (Rectangle {:color side-color})
              (Sized {:size x-side-size
                      :child (Rectangle {:color side-color})})
              (Sized {:size x-side-size
                      :child (Rectangle {:color side-color})})
              (Sized {:size y-side-size
                      :child (Rectangle {:color side-color})})
              (Sized {:size y-side-size
                      :child (Rectangle {:color side-color})})]}))
  (local cuboid (cuboid-builder ctx))
  (local front-face (. (or (and cuboid cuboid.faces) []) 1))

  (fn measurer [self]
    (front-layout:measurer)
    (update-depth dialog-depth)
    (cuboid.layout:measurer)
    (set self.measure cuboid.layout.measure))

  (fn layouter [self]
    (update-depth (or (and self.size self.size.z) 0))
    (set cuboid.layout.size self.size)
    (set cuboid.layout.position self.position)
    (set cuboid.layout.rotation self.rotation)
    (set cuboid.layout.depth-offset-index self.depth-offset-index)
    (set cuboid.layout.clip-region self.clip-region)
    (cuboid.layout:layouter)

    (local yspacing (or options.yspacing 0))
    (local body-height (math.max 0 (- self.size.y (+ titlebar-height yspacing))))
    (local depth (math.max 0 self.size.z))
    (local inset (resolve-inset options))
    (local body-depth (math.max 0 (or body-measure-depth 0)))
    (local z-offset
      (math.max 0 (math.min inset (- depth body-depth))))
    (set body.layout.size (glm.vec3 self.size.x body-height body-depth))
    (set body.layout.position
         (+ self.position (self.rotation:rotate (glm.vec3 0 0 z-offset))))
    (set body.layout.rotation self.rotation)
    (set body.layout.depth-offset-index self.depth-offset-index)
    (set body.layout.clip-region self.clip-region)
    (body.layout:layouter))

  (local layout
    (Layout {:name "deep-dialog"
             :children [cuboid.layout body.layout]
             : measurer
             : layouter}))

  (fn drop [self]
    (self.layout:drop)
    (cuboid:drop)
    (body:drop))

  {:layout layout
   :drop drop
   :cuboid cuboid
   :front front-face
   :titlebar titlebar
   :body body})

(fn DeepDialog [opts]
  (local options (or opts {}))

  (fn copy-table [source]
    (local clone {})
    (when source
      (each [k v (pairs source)]
        (set (. clone k) v)))
    clone)

  (fn build [ctx runtime-opts]
    (var dialog nil)
    (var closed? false)
    (local build-opts {})
    (local incoming (or runtime-opts {}))
    (local base-runtime-opts (copy-table incoming))
    (set base-runtime-opts.on-close nil)
    (set base-runtime-opts.actions nil)
    (local parent-target ctx.pointer-target)

    (fn resolve-target [target]
      (if (and app.hud (= target app.hud))
          app.hud
          (if (and app.scene (= target app.scene))
              app.scene
              (if target target nil))))

    (fn resolve-destination [current]
      (if (and current (= current app.hud))
          app.scene
          (if (and current (= current app.scene))
              app.hud
              (or app.hud app.scene))))

    (fn detach-from-target [target]
      (var removed false)
      (local target-element (or dialog.__scene_wrapper dialog))
      (if (and target target.remove-panel-child target-element)
          (set removed (target:remove-panel-child target-element))
          (when (and dialog dialog.drop)
            (dialog:drop)
            (set removed true)))
      (when (and (not removed) dialog dialog.drop)
        (dialog:drop))
      removed)

    (fn attach-to-target [target]
      (when (and target target.add-panel-child)
        (target:add-panel-child {:builder (DeepDialog options)
                                :builder-options (copy-table base-runtime-opts)
                                :skip-cuboid true})))

    (each [key value (pairs options)]
      (when (and (not (= key :actions))
                 (not (= key :on-close)))
        (set (. build-opts key) value)))
    (each [key value (pairs incoming)]
      (when (and (not (= key :actions))
                 (not (= key :on-close)))
        (set (. build-opts key) value)))

    (local combined-actions [])
    (each [_ action (ipairs (or options.actions []))]
      (table.insert combined-actions action))
    (each [_ action (ipairs (or incoming.actions []))]
      (table.insert combined-actions action))

    (local user-on-close (or incoming.on-close options.on-close))
    (fn handle-close [button event]
      (when (not closed?)
        (set closed? true)
        (when user-on-close
          (user-on-close dialog button event))
        (when (and (not user-on-close) dialog)
          (dialog:drop))))

    (fn handle-toggle [_button _event]
      (when (and (not closed?) dialog)
        (local current (or (resolve-target dialog.__parent_target)
                           (resolve-target parent-target)
                           app.scene
                           app.hud))
        (local destination (resolve-destination current))
        (when destination
          (detach-from-target current)
          (set dialog (attach-to-target destination)))))

    (table.insert combined-actions
                  {:name "toggle scene-hud"
                   :icon "move_item"
                   :on-click handle-toggle})
    (table.insert combined-actions {:name "close"
                                    :icon "close"
                                    :on-click handle-close})
    (set build-opts.actions combined-actions)

    (set dialog (build-deep-dialog-cuboid ctx build-opts incoming))
    (set dialog.__parent_target (resolve-target parent-target))
    dialog)

  build)

DeepDialog

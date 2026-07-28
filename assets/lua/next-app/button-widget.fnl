(local glm (require :glm))

(local Signal (require :signal))
(local TextStyle (require :text-style))
(local {: resolve-button-colors} (require :widget-theme-utils))

(local NextLayout (require :next-app/layout))
(local Node NextLayout.Node)
(local NextFlex (require :next-app/flex))
(local PanelWidget (require :next-app/panel-widget))
(local TextWidget (require :next-app/text-widget))

(fn normalize-padding [padding]
  (if (and padding (= (type padding) :table))
      {:x (or (. padding :x) (. padding 1) 0.07)
       :y (or (. padding :y) (. padding 2) 0.05)}
      {:x (or padding 0.07)
       :y (or padding 0.05)}))

(fn world-position [node]
  (local p (* node.world-matrix (glm.vec4 0 0 0 1)))
  (glm.vec3 p.x p.y p.z))

(fn resolved-position [node world-valid?]
  (if world-valid?
      (world-position node)
      (glm.vec3 node.local-x node.local-y node.local-z)))

(fn resolve-icon-codepoint [icons icon]
  (if icons
      (if icons.get
          (icons:get icon)
          (if icons.resolve
              (let [resolved (icons:resolve icon)]
                (and resolved resolved.codepoint))
              nil))
      nil))

(fn build-trailing-node [trailing]
  (if (not trailing)
      nil
      (if (= (type trailing) :function)
          (trailing)
          trailing)))

(fn ButtonWidget [opts]
  (local options (or opts {}))
  (local resolved-colors (resolve-button-colors {:theme options.theme} options))
  (local padding (normalize-padding (or options.padding [0.07 0.05])))
  (local content-spacing (or options.content-spacing 0.06))
  (local focus-outline-width (or options.focus-outline-width 0.02))
  (local focusable? (not (= options.focusable? false)))
  (local focus-context options.focus)
  (local clickables (assert options.clickables "ButtonWidget requires clickables"))
  (local hoverables (assert options.hoverables "ButtonWidget requires hoverables"))
  (local system-cursors options.system-cursors)

  (local base-text-style
    (or options.text-style
        (TextStyle {:color resolved-colors.foreground
                    :scale (or options.text-scale 0.06)})))
  (local label-text
    (if (not (= options.text nil))
        options.text
        (if options.icon nil "Button")))
  (local label-node
    (and label-text
         (TextWidget {:name (or options.label-name "next-button-label")
                      :text label-text
                      :style base-text-style})))
  (local icon-node
    (if options.icon
        (let [icons options.icons
              cp (resolve-icon-codepoint icons options.icon)
              icon-font (or (and options.icon-style options.icon-style.font)
                            (and icons icons.font)
                            base-text-style.font)
              icon-scale (or (and options.icon-style options.icon-style.scale)
                             (and options.icon-style options.icon-style.size)
                             base-text-style.scale)
              icon-color (or (and options.icon-style options.icon-style.color)
                             resolved-colors.foreground)]
          (assert cp "ButtonWidget icon option requires icons:get/resolve")
          (assert icon-font "ButtonWidget icon requires resolved icon font")
          (TextWidget {:name (or options.icon-name "next-button-icon")
                       :codepoints [cp]
                       :style {:font icon-font
                               :scale icon-scale
                               :color icon-color}}))
        nil))
  (local trailing-node (build-trailing-node options.trailing))
  (local custom-child options.child)

  (local content-node
    (if custom-child
        custom-child
        (let [children []]
          (when icon-node
            (table.insert children (NextFlex.FlexChild icon-node 0)))
          (when label-node
            (table.insert children (NextFlex.FlexChild label-node 0)))
          (when trailing-node
            (table.insert children (NextFlex.FlexChild trailing-node 0)))
          (if (= (length children) 0)
              (TextWidget {:name "next-button-empty"
                           :text ""
                           :style base-text-style})
              (if (= (length children) 1)
                  (. (. children 1) :node)
                  (NextFlex.Flex {:name (or options.content-name "next-button-content")
                                  :axis :x
                                  :gap content-spacing
                                  :children children}))))
        ))

  (local background-node
    (PanelWidget {:name (or options.background-name "next-button-bg")
                  :padding [0 0]
                  :color resolved-colors.background}))
  (local focus-overlay-node
    (and focusable?
         (PanelWidget {:name (or options.focus-name "next-button-focus")
                       :padding [0 0]
                       :color resolved-colors.focus-outline
                       :visible? false})))

  (var button nil)
  (var focus-target-node nil)
  (var focus-manager nil)
  (var focus-focus-listener nil)
  (var focus-blur-listener nil)
  (var hovered? false)
  (var pressed? false)
  (var focused? false)
  (var enabled? (not (= options.enabled? false)))
  (var background-color resolved-colors.background)
  (var hover-background-color resolved-colors.hover)
  (var pressed-background-color resolved-colors.pressed)
  (var foreground-color resolved-colors.foreground)
  (local variant resolved-colors.variant)
  (local ghost? (= variant :ghost))
  (var disabled-background-color nil)

  (fn update-background-color [_self]
    (local color
      (if pressed?
          pressed-background-color
          (if hovered?
              hover-background-color
              background-color)))
    (background-node:set-color color)
    (if ghost?
        (background-node:set-visible (or hovered? pressed?))
        (background-node:set-visible true)))

  (fn update-focus-visual [_self]
    (when focus-overlay-node
      (focus-overlay-node:set-visible focused?)))

  (fn register-clickables []
    (when clickables
      (when clickables.register
        (clickables:register button))
      (when clickables.register-right-click
        (clickables:register-right-click button))
      (when clickables.register-double-click
        (clickables:register-double-click button))))

  (fn unregister-clickables []
    (when clickables
      (when clickables.unregister
        (clickables:unregister button))
      (when clickables.unregister-right-click
        (clickables:unregister-right-click button))
      (when clickables.unregister-double-click
        (clickables:unregister-double-click button))))

  (fn register-hoverables []
    (when (and hoverables hoverables.register)
      (hoverables:register button)))

  (fn unregister-hoverables []
    (when (and hoverables hoverables.unregister)
      (hoverables:unregister button)))

  (fn set-focus-state [_self value]
    (set focused? (not (= value false)))
    (set button.focused? focused?)
    (update-focus-visual nil)
    (update-background-color nil))

  (fn get-focus-bounds []
    {:position (world-position button)
     :size (glm.vec3 button.width
                     button.height
                     (if (= button.depth 0) 0.01 button.depth))})

  (fn measure-fn [self max-width max-height max-depth]
    (content-node:run-measure (math.max 0 (- max-width (* padding.x 2)))
                              (math.max 0 (- max-height (* padding.y 2)))
                              max-depth)
    (self:set-measure (+ content-node.measured-width (* padding.x 2))
                      (+ content-node.measured-height (* padding.y 2))
                      0))

  (fn layout-fn [self width height depth]
    (self:set-size width height depth {:mark-dirty? false})

    (when focus-overlay-node
      (focus-overlay-node:layout-set-frame (- 0 focus-outline-width)
                                           (- 0 focus-outline-width)
                                           -0.003
                                           (+ width (* focus-outline-width 2))
                                           (+ height (* focus-outline-width 2))
                                           0
                                           (glm.quat 1 0 0 0))
      (focus-overlay-node:run-layout focus-overlay-node.width focus-overlay-node.height focus-overlay-node.depth))

    (background-node:layout-set-frame 0
                                      0
                                      -0.001
                                      width
                                      height
                                      0
                                      (glm.quat 1 0 0 0))
    (background-node:run-layout background-node.width background-node.height background-node.depth)

    (local content-width (math.min content-node.measured-width (math.max 0 (- width (* padding.x 2)))))
    (local content-height (math.min content-node.measured-height (math.max 0 (- height (* padding.y 2)))))
    (local content-x (/ (- width content-width) 2))
    (local content-y (/ (- height content-height) 2))
    (content-node:layout-set-frame content-x
                                   content-y
                                   -0.002
                                   content-width
                                   content-height
                                   0
                                   (glm.quat 1 0 0 0))
    (content-node:run-layout content-node.width content-node.height content-node.depth))

  (set button
       (Node.new {:name (or options.name "next-button")
                  :measure-fn measure-fn
                  :layout-fn layout-fn}))
  (when focus-overlay-node
    (button:add-child focus-overlay-node))
  (button:add-child background-node)
  (button:add-child content-node)

  (local clicked (Signal))
  (local right-clicked (Signal))
  (local double-clicked (Signal))

  (set button.clicked clicked)
  (set button.right-clicked right-clicked)
  (set button.double-clicked double-clicked)
  (set button.focus-overlay focus-overlay-node)
  (set button.focus-node nil)
  (set button.focus-manager nil)
  (set button.focus-outline-width focus-outline-width)
  (set button.focus-outline-color resolved-colors.focus-outline)
  (set button.rectangle background-node)
  (set button.child content-node)
  (set button.text (or label-node icon-node))
  (set button.label label-node)
  (set button.icon options.icon)
  (set button.hovered? hovered?)
  (set button.pressed? pressed?)
  (set button.focused? focused?)
  (set button.enabled? enabled?)
  (set button.background-color background-color)
  (set button.hover-background-color hover-background-color)
  (set button.pressed-background-color pressed-background-color)
  (set button.foreground-color foreground-color)
  (set button.variant variant)
  (set button.ghost? ghost?)

  (set button.update-background-color
       (fn [self]
         (update-background-color self)
         (set self.hovered? hovered?)
         (set self.pressed? pressed?)))
  (set button.emit-quads
       (fn [_self quad-batcher clip-matrix]
         (background-node:emit-quads quad-batcher clip-matrix)
         (when focus-overlay-node
           (focus-overlay-node:emit-quads quad-batcher clip-matrix))))
  (set button.update-focus-visual
       (fn [self]
         (update-focus-visual self)
         (set self.focused? focused?)))
  (set button.request-focus
       (fn [self]
         (if focus-target-node
             (focus-target-node:request-focus {:reason :pointer})
             (set-focus-state self true))))
  (set button.on-click
       (fn [self event]
         (self:request-focus)
         (clicked:emit event)))
  (set button.on-right-click
       (fn [_self event]
         (right-clicked:emit event)))
  (set button.on-double-click
       (fn [_self event]
         (double-clicked:emit event)))
  (set button.on-hovered
       (fn [self entered]
         (set hovered? (not (= entered false)))
         (set self.hovered? hovered?)
         (when system-cursors
           (system-cursors:set-cursor (if hovered? "hand" "arrow")))
         (self:update-background-color)))
  (set button.on-pressed
       (fn [self pressed]
         (set pressed? (not (= pressed false)))
         (set self.pressed? pressed?)
         (self:update-background-color)))
  (set button.set-enabled
       (fn [self value]
         (local next (not (= value false)))
         (when (not (= enabled? next))
           (set enabled? next)
           (set self.enabled? enabled?)
           (if enabled?
               (do
                 (when disabled-background-color
                   (set background-color disabled-background-color))
                 (when focus-target-node
                   (set focus-target-node.can-request-focus? true)
                   (set focus-target-node.skip-traversal? false))
                 (register-clickables)
                 (register-hoverables))
               (do
                 (when (not disabled-background-color)
                   (set disabled-background-color background-color))
                 (set background-color (glm.vec4 0.25 0.25 0.25 0.5))
                 (set hovered? false)
                 (set pressed? false)
                 (set focused? false)
                 (set self.focused? false)
                 (when focus-target-node
                   (set focus-target-node.can-request-focus? false)
                   (set focus-target-node.skip-traversal? true)
                   (when (and focus-manager
                              (= (focus-manager:get-focused-node) focus-target-node))
                     (focus-manager:clear-focus)))
                 (unregister-clickables)
                 (unregister-hoverables)
                 (self:update-focus-visual)))
           (set self.background-color background-color)
           (self:update-background-color))))
  (set button.set-text
       (fn [self text]
         (when label-node
           (label-node:set-text text)
           (self:mark-measure-dirty))))
  (set button.set-color
       (fn [self color]
         (set background-color (or color background-color))
         (set self.background-color background-color)
         (self:update-background-color)))
  (set button.intersect
       (fn [self ray]
         (local origin (and ray ray.origin))
         (local direction (and ray ray.direction))
         (if (and origin direction)
             (let [world-valid? (not self._transform-dirty)
                   position (resolved-position self world-valid?)
                   z position.z
                   t (if (= direction.z 0)
                         (if (< (math.abs (- origin.z z)) 0.000001) 0 nil)
                         (/ (- z origin.z) direction.z))]
               (if (or (= t nil) (< t 0))
                   (values false nil nil)
                   (let [px (+ origin.x (* direction.x t))
                         py (+ origin.y (* direction.y t))
                         minx position.x
                         miny position.y
                         maxx (+ minx self.width)
                         maxy (+ miny self.height)]
                     (if (and (>= px minx) (<= px maxx)
                              (>= py miny) (<= py maxy))
                         (values true (glm.vec3 px py z) t)
                         (values false nil nil)))))
             (values false nil nil))))
  (set button.drop
       (fn [self]
         (unregister-clickables)
         (unregister-hoverables)
         (self.clicked:clear)
         (self.right-clicked:clear)
         (self.double-clicked:clear)
         (when focus-focus-listener
           (when (and focus-manager focus-manager.focus-focus)
             (focus-manager.focus-focus.disconnect focus-focus-listener true))
           (set focus-focus-listener nil))
         (when focus-blur-listener
           (when (and focus-manager focus-manager.focus-blur)
             (focus-manager.focus-blur.disconnect focus-blur-listener true))
           (set focus-blur-listener nil))
         (when focus-target-node
           (focus-target-node:drop)
           (set focus-target-node nil)
           (set self.focus-node nil))))

  (when options.on-click
    (clicked.connect (fn [event] (options.on-click button event))))
  (when options.on-right-click
    (right-clicked.connect (fn [event] (options.on-right-click button event))))
  (when options.on-double-click
    (double-clicked.connect (fn [event] (options.on-double-click button event))))

  (register-clickables)
  (register-hoverables)
  (when (and focus-context focusable?)
    (set focus-target-node
         (focus-context:create-node {:name (or options.focus-name options.name options.text "next-button")}))
    (set focus-manager (and focus-target-node focus-target-node.manager))
    (set focus-target-node.get-focus-bounds get-focus-bounds)
    (when (and focus-context focus-context.attach-bounds)
      (focus-context:attach-bounds focus-target-node {:get-focus-bounds get-focus-bounds}))
    (set button.focus-node focus-target-node)
    (set button.focus-manager focus-manager)
    (when (and focus-manager focus-manager.focus-focus)
      (set focus-focus-listener
           (focus-manager.focus-focus.connect
             (fn [event]
               (when (and event (= event.current focus-target-node))
                 (set-focus-state button true))))))
    (when (and focus-manager focus-manager.focus-blur)
      (set focus-blur-listener
           (focus-manager.focus-blur.connect
             (fn [event]
               (when (and event (= event.previous focus-target-node))
                 (set-focus-state button false))))))
    (when (= (and focus-manager (focus-manager:get-focused-node)) focus-target-node)
      (set-focus-state button true))
    (when (not focus-target-node.activate)
      (set focus-target-node.activate
           (fn [_node activate-opts]
             (button:on-click (or (and activate-opts activate-opts.event) {:source :keyboard}))
             true))))
  (button:update-background-color)
  (button:update-focus-visual)
  (when (not enabled?)
    (button:set-enabled false))

  button)

ButtonWidget

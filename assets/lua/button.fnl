(local glm (require :glm))
(local Aligned (require :aligned))
(local Padding (require :padding))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Rectangle (require :rectangle))
(local Stack (require :stack))
(local {: Flex : FlexChild} (require :flex))
(local Signal (require :signal))
(local {: resolve-button-colors} (require :widget-theme-utils))
(local {: resolve-mark-flag} (require :layout))

(local colors (require :colors))
(fn attach-focus-overlay-layouter [stack focus-rectangle focus-outline-width]
  (when (and stack stack.layout focus-rectangle)
    (set stack.layout.layouter
         (fn [layout]
           (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
           (local position (or layout.position (glm.vec3 0 0 0)))
           (local size (or layout.size layout.measure (glm.vec3 0 0 0)))
           (local depth-index (or layout.depth-offset-index 0))
           (local clip layout.clip-region)
           (each [i child (ipairs stack.children)]
             (local child-layout child.layout)
             (if (= child focus-rectangle)
                 (do
                   (local thickness (or focus-outline-width 0))
                   (local doubled (* thickness 2))
                   (local expanded (+ size (glm.vec3 doubled doubled 0)))
                   (local offset (rotation:rotate (glm.vec3 (- thickness) (- thickness) 0)))
                   (set child-layout.size expanded)
                   (set child-layout.position (+ position offset)))
                 (do
                   (set child-layout.size size)
                   (set child-layout.position position)))
             (set child-layout.rotation rotation)
             (set child-layout.depth-offset-index (+ depth-index i))
             (set child-layout.clip-region clip)
             (child-layout:layouter))))))
(fn Button [opts]
  (local options (or opts {}))

  (fn build [ctx]
    (local colors (resolve-button-colors ctx options))
    (local base-text-style
      (or options.text-style
          (TextStyle {:color colors.foreground})))
    (fn make-text [value]
      (Text {:text value
             :style base-text-style}))

(local Icon (require :icon-widget))

    (fn make-icon-span []
       (local icons (and ctx ctx.icons))
       (assert icons "Button icon option requires ctx.icons")
       (local icon-name options.icon)
       (local icon-color 
         (if (and options.icon-style options.icon-style.color)
             options.icon-style.color
             colors.foreground))

       (Icon {:icon icon-name
              :color icon-color
              ;; Pass through other style properties if needed, or assume Icon handles defaults
              :size (and options.icon-style options.icon-style.size)}))

    (local icon-builder (and options.icon (make-icon-span)))
    (local label-text
      (if (not (= options.text nil))
          options.text
          (if options.icon nil "Button")))
    (local trailing-builder options.trailing)
    (when trailing-builder
      (assert (= (type trailing-builder) :function)
              "Button trailing requires a builder"))
    (local content-builder
      (if options.child
          options.child
          (let [builders []
                spacing (or options.content-spacing 0.35)]
            (when icon-builder
              (table.insert builders icon-builder))
            (when label-text
              (table.insert builders (make-text label-text)))
            (when trailing-builder
              (table.insert builders trailing-builder))
            (local resolved
              (if (= (length builders) 1)
                  (. builders 1)
                  (Flex {:axis 1
                         :xspacing spacing
                         :yalign :center
                         :children (icollect [_ builder (ipairs builders)]
                                             (FlexChild builder 0))})))
            (Padding {:child resolved
                      :edge-insets (or options.padding [0.5 0.5])}))))
    (local aligned-options {:child content-builder})
    (if (or (not (= options.xalign nil))
            (not (= options.yalign nil))
            (not (= options.align nil)))
        (do
          (set aligned-options.xalign options.xalign)
          (set aligned-options.yalign options.yalign)
          (set aligned-options.align options.align))
        (do
          (set aligned-options.axis :y)
          (set aligned-options.alignment :center)))
    (local aligned-builder (Aligned aligned-options))
    (local focus-context (and ctx ctx.focus))
    (local focusable? (and focus-context (not (= options.focusable? false))))
    (local focus-outline-width (or options.focus-outline-width 0.15))
    (local rectangle-builder
      (Rectangle {:color colors.background}))
    (local focus-outline-builder
      (and focusable? (Rectangle {:color colors.focus-outline})))
    (local stack-children [])
    (when focus-outline-builder
      (table.insert stack-children focus-outline-builder))
    (table.insert stack-children rectangle-builder)
    (table.insert stack-children aligned-builder)
    (local stack-builder
      (Stack {:children stack-children}))
    (local pointer-target (and ctx ctx.pointer-target))
    (local clickables (assert ctx.clickables "Button requires ctx.clickables"))
    (local hoverables (assert ctx.hoverables "Button requires ctx.hoverables"))
    (local system-cursors (and ctx ctx.system-cursors))
    (local stack (stack-builder ctx))
    (var button nil)
    (local focus-rectangle (and focus-outline-builder (. stack.children 1)))

    (when focus-rectangle
      (focus-rectangle:set-visible false {:mark-layout-dirty? false}))
    (local rectangle (. stack.children (if focus-rectangle 2 1)))
    (local aligned (. stack.children (if focus-rectangle 3 2)))
    (local child aligned.child)
    (local padding (and (not options.child) child))
    (local text (and padding padding.child))
    (local focus-node
      (and focusable?
           (focus-context:create-node {:name (or options.focus-name options.name options.text "button")})))
    (when (and focus-node focus-context stack stack.layout)
      (focus-context:attach-bounds focus-node {:layout stack.layout}))
    (local focus-manager (and focus-node focus-node.manager))
    (var focus-listener nil)
    (local clicked (Signal))
    (local right-clicked (Signal))
    (local double-clicked (Signal))
    (set button
      {:layout stack.layout
       :stack stack
       :focus-node focus-node
       :focus-overlay focus-rectangle
       :focus-outline-color colors.focus-outline
       :focus-outline-width focus-outline-width
       :focus-manager focus-manager
       :rectangle rectangle
       :child child
       :padding padding
       :aligned aligned
       :text text
       :icon options.icon
       :background-color colors.background
       :hover-background-color colors.hover
       :pressed-background-color colors.pressed
       :focused-background-color colors.focused-background
       :foreground-color colors.foreground
       :variant colors.variant
       :ghost? (= colors.variant :ghost)
       :hovered? false
       :pressed? false
       :focused? false
       :clicked clicked
       :right-clicked right-clicked
       :double-clicked double-clicked
       :pointer-target pointer-target})

    (attach-focus-overlay-layouter stack focus-rectangle focus-outline-width)

    ;; Connect built-in handlers to signals so emitting once fans out everywhere.
    (when options.on-click
      (clicked.connect (fn [event]
                         (options.on-click button event))))
    (when options.on-right-click
      (right-clicked.connect (fn [event]
                               (options.on-right-click button event))))
    (when options.on-double-click
      (double-clicked.connect (fn [event]
                                (options.on-double-click button event))))

    (fn register-clickables []
      (clickables:register button)
      (clickables:register-right-click button)
      (clickables:register-double-click button))

    (fn unregister-clickables []
      (clickables:unregister button)
      (clickables:unregister-right-click button)
      (clickables:unregister-double-click button))

    (fn register-hoverables []
      (hoverables:register button))

    (fn unregister-hoverables []
      (hoverables:unregister button))

    (fn update-background-color [self opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (local color
        (if self.pressed?
            self.pressed-background-color
            (if self.hovered?
                self.hover-background-color
                self.background-color)))
      (local rect self.rectangle)
      (when rect
        (local show-background
          (if self.ghost?
              (or self.hovered? self.pressed?)
              true))
        (rect:set-visible show-background {:mark-layout-dirty? mark-layout-dirty?})
        (when show-background
          (set rect.color color))
        (when (and mark-layout-dirty? rect.layout)
          (rect.layout:mark-layout-dirty))))

    (fn update-focus-visual [self opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (local overlay self.focus-overlay)
      (when overlay
        (local show (and self.focused? true))
        (overlay:set-visible show {:mark-layout-dirty? mark-layout-dirty?})
        (when (and show overlay.layout self.layout self.layout.size)
          (local overlay-layout overlay.layout)
          (local layout self.layout)
          (local thickness (or self.focus-outline-width 0))
          (local doubled (* thickness 2))
          (local expanded (+ layout.size (glm.vec3 doubled doubled 0)))
          (set overlay-layout.size expanded)
          (local offset (glm.vec3 (- thickness) (- thickness) 0))
          (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
          (local rotated (rotation:rotate offset))
          (local base-position (or layout.position (glm.vec3 0 0 0)))
          (set overlay-layout.position (+ base-position rotated))
          (set overlay-layout.rotation rotation)
          (when mark-layout-dirty?
            (overlay.layout:mark-layout-dirty))
          (overlay.layout:layouter)))
      )

    (fn set-focus-state [focused? opts]
      (when (not (= button.focused? focused?))
        (set button.focused? (not (not focused?)))
        (button:update-focus-visual opts)
        (button:update-background-color opts)))

    (set button.intersect (fn [self ray]
                            (self.layout:intersect ray)))
    (set button.request-focus
         (fn [self]
           (when self.focus-node
             (self.focus-node:request-focus))))
    (set button.on-click (fn [self event]
                           (self:request-focus)
                           (when self.focus-manager
                             (self.focus-manager:arm-auto-focus {:event event}))
                           (clicked:emit event)
                           (when self.focus-manager
                             (self.focus-manager:clear-auto-focus))))
    (set button.on-right-click (fn [_self event]
                                 (right-clicked:emit event)))
    (set button.on-double-click (fn [_self event]
                                  (double-clicked:emit event)))
    (set button.on-hovered
         (fn [self entered]
           (set self.hovered? entered)
           (when system-cursors
             (system-cursors:set-cursor (if entered "hand" "arrow")))
           (self:update-background-color)))
    (set button.on-pressed
         (fn [self pressed]
           (set self.pressed? pressed)
           (self:update-background-color)))
    (set button.update-background-color update-background-color)
    (set button.update-focus-visual update-focus-visual)
    (when (and focus-manager focus-node)
      (set button.__focus-focus-listener
           (focus-manager.focus-focus.connect
             (fn [event]
               (when (and event (= event.current focus-node))
                 (set-focus-state true)))))
      (set button.__focus-blur-listener
           (focus-manager.focus-blur.connect
             (fn [event]
               (when (and event (= event.previous focus-node))
                 (set-focus-state false)))))
      (when (= (focus-manager:get-focused-node) focus-node)
        (set-focus-state true {:mark-layout-dirty? false})))
    (when (and focus-node (not focus-node.activate))
      (set focus-node.activate
           (fn [_node opts]
             (local event (or (and opts opts.event) {:source :keyboard}))
             (button:on-click event)
             true)))
    (set button.drop
         (fn [self]
           (unregister-clickables)
           (unregister-hoverables)
           (self.clicked:clear)
           (self.right-clicked:clear)
           (self.double-clicked:clear)
           (when self.__focus-focus-listener
             (local manager self.focus-manager)
             (when (and manager manager.focus-focus)
               (manager.focus-focus.disconnect self.__focus-focus-listener true))
             (set self.__focus-focus-listener nil))
           (when self.__focus-blur-listener
             (local manager self.focus-manager)
             (when (and manager manager.focus-blur)
               (manager.focus-blur.disconnect self.__focus-blur-listener true))
             (set self.__focus-blur-listener nil))
           (when self.focus-node
             (self.focus-node:drop)
             (set self.focus-node nil))
            (self.stack:drop)))

    (register-hoverables)
    (register-clickables)
    (button:update-background-color {:mark-layout-dirty? false})
    (button:update-focus-visual {:mark-layout-dirty? false})
    button))

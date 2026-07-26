(local glm (require :glm))
(local InputState (require :input-state-router))
(local {: Layout} (require :layout))
(local {: resolve-style
        : fallback-glyph
        : line-height} (require :text-utils))
(local RuntimeUpdates (require :runtime-updates))
(local TerminalRenderer (require :terminal-renderer))
(local terminal (require :terminal))
(local Modifiers (require :input-modifiers))

(fn negate-vec3 [value]
  (glm.vec3 (- value.x)
            (- value.y)
            (- value.z)))

(fn resolve-frame-padding [options cell-size]
  (local value (or options.frame-padding
                   (glm.vec2 (* cell-size.x 0.25)
                             (* cell-size.y 0.25))))
  (if (= (type value) "number")
      (glm.vec2 value value)
      (glm.vec2 (or (. value 1) value.x value.width 0)
                (or (. value 2) value.y value.height 0))))

(fn resolve-cell-size [ctx opts style]
  (local options (or opts {}))
  (if options.cell-size
      (let [value options.cell-size
            kind (type value)]
        (if (= kind "number")
            (glm.vec2 value value)
            (if (= kind "table")
                (glm.vec2 (or (. value 1) value.x value.width 1)
                      (or (. value 2) value.y value.height 1))
                (glm.vec2 1 1))))
      (let [style (or style (resolve-style ctx options))
            space-codepoint (string.byte " ")
            glyph (fallback-glyph style.font space-codepoint)
            advance (or (and glyph glyph.advance) 1)]
        (glm.vec2 (* advance style.scale)
              (line-height style)))))

(fn TerminalWidget [opts]
  (local options (or opts {}))

  (fn build [ctx]
    (local style (resolve-style ctx options))
    (local cell-size (resolve-cell-size ctx options style))
    (local desired-frame-padding (resolve-frame-padding options cell-size))
    (var rows (or options.rows 72))
    (var cols (or options.cols 240))
    (local scrollback-lines (or (. options "scrollback-lines") 8000))
    (local enable-alt-screen? (not (= (. options "enable-alt-screen?") false)))
    (var follow-tail? (not (= (. options "follow-tail?") false)))
    (var scroll-offset (math.max 0 (or options.scroll_offset 0)))
    (var last-scrollback-size 0)
    (local on-scroll (. options "on-scroll"))
    (when (> scroll-offset 0)
      (set follow-tail? false))
    (var term (terminal.Terminal rows cols))
    (local pty-available? (and term term.is-pty-available (term:is-pty-available)))
    (when (and (not pty-available?) term term.inject-output)
      (term:inject-output (.. "PTY unavailable (sandboxed?).\r\n"
                                        "Terminal is running without a child process.\r\n")))
    (when (not pty-available?)
      (set scroll-offset 0)
      (set follow-tail? true))
    (when scrollback-lines
      (term:set-scrollback-limit scrollback-lines))
    (var dropped? false)
    (var update-subscription nil)
    (local pointer-target (and ctx ctx.pointer-target))
    (local clickables (assert ctx.clickables "TerminalWidget requires ctx.clickables"))
    (local focus-context (and ctx ctx.focus))
    (local focusable? (and focus-context (not (= options.focusable? false))))
    (local focus-node
      (and focusable?
           (focus-context:create-node {:name (or options.focus-name
                                                 options.name
                                                 "terminal")})))
    (local focus-manager (and focus-node focus-node.manager))
    (var focused? false)
    (var connected? false)
    (local renderer (TerminalRenderer {:ctx ctx
                                       :style style
                                       :cell-size cell-size}))
    (renderer:set-term term)
    (renderer:set-grid-size rows cols)

    (when options.on-bell
      (set term.on-bell options.on-bell))
    (when options.on-title
      (set term.on-title-changed options.on-title))
    (set term.on-screen-updated (fn [] (renderer:mark-dirty {})))
    (set term.on-cursor-moved (fn [_row _col] (renderer:mark-dirty {})))

    (local measurer
      (fn [self]
        (set self.measure (glm.vec3 (* cols cell-size.x)
                                (* rows cell-size.y)
                                0))))

    (local layouter
      (fn [self]
        (local allocated-size (or self.size self.measure))
        (local allocated-position self.position)
        (local max-frame-padding-x (math.max 0 (/ (- allocated-size.x cell-size.x) 2)))
        (local max-frame-padding-y (math.max 0 (/ (- allocated-size.y cell-size.y) 2)))
        (local frame-padding (glm.vec2 (math.min desired-frame-padding.x max-frame-padding-x)
                                       (math.min desired-frame-padding.y max-frame-padding-y)))
        (local usable-size (glm.vec3 (math.max cell-size.x (- allocated-size.x (* 2 frame-padding.x)))
                                     (math.max cell-size.y (- allocated-size.y (* 2 frame-padding.y)))
                                     0))
        (local next-cols (math.max 1 (math.floor (/ usable-size.x (math.max cell-size.x 0.0001)))))
        (local next-rows (math.max 1 (math.floor (/ usable-size.y (math.max cell-size.y 0.0001)))))
        (local snapped-size (glm.vec3 (* next-cols cell-size.x)
                                      (* next-rows cell-size.y)
                                      0))
        (local extra-x (math.max 0 (- usable-size.x snapped-size.x)))
        (local extra-y (math.max 0 (- usable-size.y snapped-size.y)))
        (local position-offset (glm.vec3 (+ frame-padding.x (/ extra-x 2))
                                         (+ frame-padding.y (/ extra-y 2))
                                         0))
        (when (or (not (= next-cols cols))
                  (not (= next-rows rows)))
          (set cols next-cols)
          (set rows next-rows)
          (term:resize rows cols)
          (renderer:set-grid-size rows cols))
        (renderer:set-frame {:size allocated-size
                             :offset (negate-vec3 position-offset)})
        (set self.position (+ allocated-position (self.rotation:rotate position-offset)))
        (set self.size snapped-size)
        (renderer:set-layout self)))

    (local layout (Layout {:name "terminal"
                           : measurer
                           : layouter}))
    (renderer:set-layout layout)
    (when (and focus-node focus-context layout)
      (focus-context:attach-bounds focus-node {:layout layout}))

    (local connect-input
      (fn [self]
        (when (and (not connected?) InputState)
          (InputState.connect-input self)
          (set connected? true))))

    (local disconnect-input
      (fn [self]
        (when (and connected? InputState)
          (InputState.disconnect-input self)
          (set connected? false))))

    (local attach-focus-listener
      (fn [self]
        (local manager (and self.focus-node self.focus-node.manager))
        (when (and manager (not self.__focus-listener))
          (set self.__focus-listener
               (manager.focus-focus:connect
                 (fn [event]
                   (local node self.focus-node)
                   (when (and event node (= event.current node))
                     (when (not focused?)
                       (set focused? true)
                       (connect-input self)))))))
        (when (and manager (not self.__blur-listener))
          (set self.__blur-listener
               (manager.focus-blur:connect
                 (fn [event]
                   (local node self.focus-node)
                   (when (and event node (= event.previous node))
                     (when focused?
                       (set focused? false)
                       (disconnect-input self))))))))) 

    (local detach-focus-listener
      (fn [self]
        (local manager (and self.focus-node self.focus-node.manager))
        (when (and manager self.__focus-listener)
          (manager.focus-focus:disconnect self.__focus-listener true)
          (set self.__focus-listener nil))
        (when (and manager self.__blur-listener)
          (manager.focus-blur:disconnect self.__blur-listener true)
          (set self.__blur-listener nil))))

    (local alt-screen?
      (fn []
        (and enable-alt-screen? term (term:is-alt-screen))))

    (local max-scroll-offset
      (fn []
        (if (or (not term) (alt-screen?))
            0
            (math.max 0 (term:get-scrollback-size)))))
    (renderer:set-scroll-state {:offset scroll-offset
                                :alt-screen? (alt-screen?)})
    (set last-scrollback-size (max-scroll-offset))

    (local emit-scroll
      (fn []
        (when on-scroll
          (on-scroll {:offset scroll-offset
                      :follow-tail follow-tail?
                      :alt-screen? (alt-screen?)}))))

    (local assert-live
      (fn [action]
        (assert (not dropped?)
                (.. "TerminalWidget " action " after drop"))))

    (local set-scroll-offset
      (fn [self next-offset opts]
        (assert-live "set_scroll_offset")
        (if (not pty-available?)
            false
            (do
              (local desired (math.max 0 (or next-offset 0)))
              (local capped (if (alt-screen?)
                                0
                                (math.min desired (max-scroll-offset))))
              (when (not (= capped scroll-offset))
                (set scroll-offset capped)
                (if (> scroll-offset 0)
                    (set follow-tail? false)
                    (when (and opts opts.reactivate-follow?)
                      (set follow-tail? true)))
                (renderer:set-scroll-state {:offset scroll-offset
                                            :alt-screen? (alt-screen?)})
                (emit-scroll)
                true)))))

    (local set-follow-tail
      (fn [_self desired]
        (assert-live "set_follow_tail")
        (local next (not (not desired)))
        (when (not (= next follow-tail?))
          (set follow-tail? next)
          (emit-scroll))))

    (local snap-to-tail-on-input
      (fn [self]
        (assert-live "snap_to_tail_on_input")
        (when follow-tail?
          (self:set_scroll_offset 0))))

    (local key-name
      (fn [payload]
        (local key (and payload payload.key))
        (local SDLK_BACKSPACE 8)
        (local SDLK_TAB 9)
        (local SDLK_RETURN 13)
        (local SDLK_ESCAPE 27)
        (local SDLK_DELETE 127)
        (local SDLK_INSERT 1073741897)
        (local SDLK_HOME 1073741898)
        (local SDLK_PAGEUP 1073741899)
        (local SDLK_END 1073741901)
        (local SDLK_PAGEDOWN 1073741902)
        (local SDLK_RIGHT 1073741903)
        (local SDLK_LEFT 1073741904)
        (local SDLK_DOWN 1073741905)
        (local SDLK_UP 1073741906)
        (local SDLK_F1 1073741882)
        (local SDLK_F12 1073741893)
        (if (= key SDLK_BACKSPACE)
            "backspace"
            (if (= key SDLK_TAB)
                "tab"
                (if (= key SDLK_RETURN)
                    "return"
                    (if (= key SDLK_ESCAPE)
                        "escape"
                        (if (= key SDLK_DELETE)
                            "delete"
                            (if (= key SDLK_INSERT)
                                "insert"
                                (if (= key SDLK_HOME)
                                    "home"
                                    (if (= key SDLK_PAGEUP)
                                        "pageup"
                                        (if (= key SDLK_END)
                                            "end"
                                            (if (= key SDLK_PAGEDOWN)
                                                "pagedown"
                                                (if (= key SDLK_RIGHT)
                                                    "right"
                                                    (if (= key SDLK_LEFT)
                                                        "left"
                                                        (if (= key SDLK_DOWN)
                                                            "down"
                                                            (if (= key SDLK_UP)
                                                                "up"
                                                                (if (and key
                                                                         (>= key SDLK_F1)
                                                                         (<= key SDLK_F12))
                                                                    (.. "f" (+ 1 (- key SDLK_F1)))
                                                                    nil)))))))))))))))))

    (local pointer-position
      (fn [payload]
        (if (and payload payload.point)
            payload.point
            (glm.vec3 (or (and payload payload.x) 0)
                  (or (and payload payload.y) 0)
                  (or (and payload payload.z) 0)))))

    (local shift-held?
      (fn [payload]
        (Modifiers.shift-held? (and payload payload.mod))))

    (local wheel-step
      (fn [payload]
        (if (shift-held? payload)
            (math.max 1 rows)
            3)))

    (local page-step
      (fn []
        (math.max 1 (- rows 1))))

    (local adjust-scroll-offset
      (fn [self delta opts]
        (assert-live "adjust_scroll_offset")
        (if (or (not pty-available?) (= delta 0))
            false
            (self:set_scroll_offset (+ scroll-offset delta) opts))))

    (local resolve-cell
      (fn [self payload]
        (assert-live "resolve_cell")
        (local point (pointer-position payload))
        (local layout-self self.layout)
        (local position (or (and layout-self layout-self.position) (glm.vec3 0 0 0)))
        (local size (or (and layout-self layout-self.size) (glm.vec3 0 0 0)))
        (local local-pos (- point position))
        (local col (math.floor (/ local-pos.x (math.max cell-size.x 0.0001))))
        (local row (math.floor (/ local-pos.y (math.max cell-size.y 0.0001))))
        (if (or (< col 0)
                (< row 0)
                (>= col cols)
                (>= row rows)
                (<= size.x 0)
                (<= size.y 0))
            nil
            {:row row :col col})))

    (local handle-mouse
      (fn [self payload button pressed?]
        (assert-live "handle_mouse")
        (local cell (resolve-cell self payload))
        (local resolved-button (or button 0))
        (if (and cell self.term)
	            (do
	              (snap-to-tail-on-input self)
	              (self.term:send-mouse cell.row cell.col resolved-button (not (not pressed?)))
	              true)
	            false)))

    (local disconnect-update
      (fn [_self]
        (when update-subscription
          (update-subscription:cancel))))

    (local connect-update
      (fn [self]
        (assert-live "connect_update")
        (update-subscription:start)))

    (local drop
      (fn [self]
        (assert-live "drop")
        (set dropped? true)
        (detach-focus-listener self)
        (disconnect-input self)
        (disconnect-update self)
        (clickables:unregister self)
        (when self.focus-node
          (self.focus-node:drop)
          (set self.focus-node nil))
        (when self.layout
          (self.layout:drop))
        (renderer:drop)
        (set self.term nil)
        (set term nil)))

    (local update
      (fn [self delta]
        (assert-live "update")
        (when self.term
          (self.term:update)
          (local current-size (if (and term term.get-scrollback-size)
                                  (term:get-scrollback-size)
                                  0))
          (local current-alt (alt-screen?))
          (when (and (not follow-tail?) (not current-alt))
            (local delta-lines (- current-size last-scrollback-size))
            (when (> delta-lines 0)
              (self:set_scroll_offset (+ scroll-offset delta-lines))))
          (set last-scrollback-size current-size)
          (local max-offset (if current-alt 0 current-size))
          (when (> scroll-offset max-offset)
            (self:set_scroll_offset max-offset {:reactivate-follow? true}))
          (renderer:set-scroll-state {:offset scroll-offset
                                      :alt-screen? current-alt}))
        (renderer:update delta)))

    (local widget
      {:term term
       :layout layout
       :drop drop
       :update update
       :connect-update connect-update
       :disconnect-update disconnect-update
       :cell-size cell-size
       :scroll_offset (fn []
                        (assert-live "scroll_offset")
                        scroll-offset)
       :set_scroll_offset set-scroll-offset
       :follow_tail (fn []
                      (assert-live "follow_tail")
                      follow-tail?)
       :set_follow_tail set-follow-tail
       :enable_alt_screen (fn []
                            (assert-live "enable_alt_screen")
                            enable-alt-screen?)
       :focus-node focus-node
       :__focus-listener nil
       :pointer-target pointer-target
       :rows (fn []
               (assert-live "rows")
               rows)
       :cols (fn []
               (assert-live "cols")
               cols)})

    (set update-subscription
         (RuntimeUpdates.FrameSubscription {:callback (fn [delta]
                                                        (widget:update delta))}))

    (set widget.on-state-connected
         (fn [_self _event]
           (assert-live "on_state_connected")
           (set connected? true)))

    (set widget.on-state-disconnected
         (fn [_self _event]
           (assert-live "on_state_disconnected")
           (set connected? false)))

    (set widget.request-focus
         (fn [self]
           (assert-live "request_focus")
           (when self.focus-node
             (self.focus-node:request-focus))))

    (set widget.on-click
         (fn [self _event]
           (assert-live "on_click")
           (self:request-focus)
           true))

    (set widget.intersect
         (fn [self ray]
           (assert-live "intersect")
           (self.layout:intersect ray)))

    (set widget.on-text-input
         (fn [self payload]
           (assert-live "on_text_input")
           (snap-to-tail-on-input self)
           (if (and self.term payload payload.text)
               (do
                 (self.term:send-text payload.text)
                 true)
               false)))

    (set widget.on-key-down
         (fn [self payload]
           (assert-live "on_key_down")
           (local name (key-name payload))
           (local handled
             (and name
                  (or (and (= name "pageup")
                           (adjust-scroll-offset self (page-step) {}))
                      (and (= name "pagedown")
                           (adjust-scroll-offset self (- (page-step))
                                                 {:reactivate-follow? true})))))
           (if handled
               true
               (do
                 (snap-to-tail-on-input self)
                 (if (and self.term name)
                     (do
                       (self.term:send-key name)
                       true)
                     false)))))

    (set widget.on-key-up
         (fn [_self _payload]
           (assert-live "on_key_up")
           true))

    (set widget.on-mouse-button-down
         (fn [self payload]
           (assert-live "on_mouse_button_down")
           (handle-mouse self payload payload.button true)))

    (set widget.on-mouse-button-up
         (fn [self payload]
           (assert-live "on_mouse_button_up")
           (handle-mouse self payload payload.button false)))

    (set widget.on-mouse-motion
         (fn [self payload]
           (assert-live "on_mouse_motion")
           (handle-mouse self payload (or (and payload payload.button) 0) (and payload payload.button))))

    (set widget.on-mouse-wheel
         (fn [self payload]
           (assert-live "on_mouse_wheel")
           (local dy (and payload payload.y))
           (if (not dy)
               false
               (do
                 (local delta (* (wheel-step payload) dy))
                 (if (adjust-scroll-offset self delta {:reactivate-follow? true})
                     true
                     (handle-mouse self payload (if (> dy 0) 4 5) true))))))

    (connect-update widget)
    (clickables:register widget)
    (attach-focus-listener widget)
    (when (and widget.focus-node focus-manager (= (focus-manager:get-focused-node) widget.focus-node))
      (set focused? true)
      (connect-input widget))
    widget))

TerminalWidget

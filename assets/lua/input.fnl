(local glm (require :glm))
(local Rectangle (require :rectangle))
(local Text (require :text))
(local TextStyle (require :text-style))
(local InputModel (require :input-model))
(local colors (require :colors))
(local gl (require :gl))
(local {: Layout : resolve-mark-flag} (require :layout))
(local {: fallback-glyph
        : line-height} (require :text-utils))
(local InputState (require :input-state-router))
(local ExternalEditor (require :external-editor))
(local {: resolve-input-colors
        : resolve-padding} (require :widget-theme-utils))

(fn current-state-name []
  (and app.engine
       app.states
       app.states.active-name
       (app.states.active-name)))

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

(fn current-active-input []
  (and InputState
       InputState.active-input
       (InputState.active-input)))

(fn standard-context-menu [input _event]
  [{:name "Copy"
    :fn (fn [_button _event]
          (local content (input:get-text))
          (gl.clipboard-set content))}
   {:name "Paste"
    :fn (fn [_button _event]
          (local value (gl.clipboard-get))
          (input:insert-text value))}
   {:name "Clear"
    :fn (fn [_button _event]
          (input:set-text ""))}])

(fn Input [opts]
  (local options (or opts {}))
  (local padding (resolve-padding options.padding))
  (local caret-width (or options.caret-width 0.05))
  (local min-width (or options.min-width 5.0))
  (local min-height (or options.min-height 1.6))
  (local placeholder-text (or options.placeholder ""))
  (local multiline? (and (= options.multiline? true)))
  (local explicit-line-count (if multiline?
                               options.line-count
                               1))
  (local resolved-min-lines
    (let [fallback (if multiline?
                       (or options.min-lines 1)
                       1)]
      (or explicit-line-count fallback)))
  (local resolved-max-lines
    (let [fallback (if multiline?
                       (or options.max-lines math.huge)
                       1)]
      (math.max resolved-min-lines (or explicit-line-count fallback))))
  (local explicit-column-count options.column-count)
  (local resolved-min-columns
    (or explicit-column-count
        (math.max 1 (or options.min-columns 1))))
  (local resolved-max-columns
    (let [fallback (or options.max-columns math.huge)]
      (math.max resolved-min-columns (or explicit-column-count fallback))))

  (fn build [ctx]
    (local model (InputModel {:text options.text}))
    (local colors (resolve-input-colors ctx options))
    (local focus-context (and ctx ctx.focus))
    (local focusable? (and focus-context (not (= options.focusable? false))))
    (local focus-node
      (and focusable?
           (focus-context:create-node {:name (or options.focus-name
                                                 options.name
                                                 "input")})))
    (local focus-manager (and focus-node focus-node.manager))
    (local focus-outline ((Rectangle {:color colors.focus-outline}) ctx))
    (focus-outline:set-visible false {:mark-layout-dirty? false})
    (local background ((Rectangle {:color colors.background}) ctx))
    (local caret ((Rectangle {:color colors.caret-normal}) ctx))
    (caret:set-visible false {:mark-layout-dirty? false})
    (local text-style
      (or options.text-style
          (TextStyle {:color colors.foreground})))
    (local text ((Text {:text (or options.text "")
                        :style text-style}) ctx))
    (local placeholder-style
      (TextStyle {:color colors.placeholder
                  :font text-style.font
                  :scale text-style.scale}))
    (local placeholder ((Text {:text placeholder-text
                               :style placeholder-style}) ctx))
    (local computed-line-height
      (let [value (line-height text-style)]
        (if (and value (> value 0))
            value
            min-height)))
    (local computed-column-width
      (let [font (and text-style text-style.font)]
        (if font
            (let [glyph (fallback-glyph font 32)
                  advance (* glyph.advance text-style.scale)]
              (if (and advance (> advance 0))
                  advance
                  caret-width))
            caret-width)))
    (var layout nil)
    (local pointer-target (and ctx ctx.pointer-target))
    (local clickables (assert ctx.clickables "Input requires ctx.clickables"))
    (local hoverables (assert ctx.hoverables "Input requires ctx.hoverables"))
    (local system-cursors (and ctx ctx.system-cursors))
    (local menu-manager (or (and ctx ctx.menu-manager) app.menu-manager))
    (local initial-visible-lines (or explicit-line-count resolved-min-lines))
  (local initial-visible-columns (or explicit-column-count resolved-min-columns))
  (var input nil)
  (set input {:__dropped false})
  (model:set-viewport-lines initial-visible-lines)
  (model:set-viewport-columns initial-visible-columns)

  (fn glyph-advance [style codepoint]
    (local font (and style style.font))
    (if (not font)
        0
        (let [glyph (fallback-glyph font codepoint)]
            (if (and glyph glyph.advance)
                (* glyph.advance style.scale)
                0))))

  (fn mark-virtual-dirty [self opts]
    (set self.virtual-dirty? true)
    (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? true))
    (when (and mark-measure-dirty? self.text self.text.layout)
      (self.text.layout:mark-measure-dirty)))

    (fn sync-viewport-state [self]
      (set self.lines self.model.lines)
      (set self.cursor-line self.model.cursor-line)
      (set self.cursor-column self.model.cursor-column)
      (when (not self.scroll)
        (set self.scroll {:line 0 :column 0}))
      (set self.scroll.line self.model.scroll-line)
      (set self.scroll.column self.model.scroll-column)
      (set self.visible-line-count self.model.viewport-lines)
      (set self.visible-column-count self.model.viewport-columns))

    (fn refresh-virtual-text [self force?]
      (when (and self.text (or self.virtual-dirty? force?))
        (set self.virtual-dirty? false)
        (self.text:set-codepoints
          (self.model:get-visible-codepoints)
          {:mark-measure-dirty? false})))

    (fn resolve-line-count [self inner-height]
      (if self.explicit-line-count
          self.explicit-line-count
          (let [line-height (math.max (or self.line-height 0) 0.0001)
                available (or inner-height 0)
                computed (if (> line-height 0)
                             (math.max 1 (math.floor (/ available line-height)))
                             self.min-lines)]
            (math.max self.min-lines (math.min self.max-lines computed)))))

    (fn resolve-column-count [self inner-width]
      (if self.explicit-column-count
          self.explicit-column-count
          (let [column-width (math.max (or self.column-width 0) 0.0001)
                available (or inner-width 0)
                computed (if (> column-width 0)
                             (math.max 1 (math.floor (/ available column-width)))
                             self.min-columns)]
            (math.max self.min-columns (math.min self.max-columns computed)))))

    (fn apply-viewport [self inner-size]
      (local next-lines (resolve-line-count self inner-size.y))
      (local next-columns (resolve-column-count self inner-size.x))
      (var changed? false)
      (when (self.model:set-viewport-lines next-lines)
        (set changed? true))
      (when (self.model:set-viewport-columns next-columns)
        (set changed? true))
      (when changed?
        (sync-viewport-state self)
        (mark-virtual-dirty self {:mark-measure-dirty? false})))

    (fn caret-vertical-offset [self]
      (local relative (- (or self.model.cursor-line 0)
                         (or self.model.scroll-line 0)))
      (local inner-height (or (and self.inner-size self.inner-size.y) 0))
      (local line-height (math.max 0 (or self.line-height 0)))
      (local top-offset (+ self.padding.y
                           (math.max 0 (- inner-height line-height))))
      (- top-offset (* (math.max 0 relative) line-height)))

    (fn cursor-prefix-width [self]
      (local lines (or self.model.lines []))
      (local line (. lines (+ self.model.cursor-line 1)))
      (if (not (and line line.codepoints))
          0
          (let [start (math.max 0 (or self.model.scroll-column 0))
                stop (math.max 0 (or self.model.cursor-column 0))]
            (if (< stop start)
                0
                (do
                  (var width 0)
                  (var column start)
                  (local style self.text.style)
                  (while (< column stop)
                    (local codepoint (. line.codepoints (+ column 1)))
                    (when codepoint
                      (set width (+ width (glyph-advance style codepoint))))
                    (set column (+ column 1)))
                  width)))))

    (fn caret-width-for-mode [self]
      (if (= self.mode :insert)
          self.caret-width
          (do
            (local style self.text.style)
            (local font (and style style.font))
            (local codepoint (. self.codepoints (+ self.cursor-index 1)))
            (if font
                (do
                  (local glyph (fallback-glyph font (or codepoint 32)))
                  (if glyph
                      (do
                        (local block-width (* glyph.advance style.scale))
                        (if (> block-width 0)
                            block-width
                            self.caret-width))
                      self.caret-width))
                self.caret-width))))

    (fn update-caret-layout [self opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (when (and self.caret self.layout self.inner-size)
        (local rotation (or self.layout.rotation (glm.quat 1 0 0 0)))
        (local position (or self.layout.position (glm.vec3 0 0 0)))
        (local clip self.layout.clip-region)
        (local depth-index (or self.layout.depth-offset-index 0))
        (local size (or self.layout.size self.layout.measure))
        (local inner-height (or self.inner-size.y 0))
        (local caret-depth (+ depth-index 2))
        (local prefix (self:cursor-prefix-width))
        (local x-offset (+ self.padding.x prefix))
        (local caret-y (caret-vertical-offset self))
        (local caret-height
          (if self.multiline?
              (math.max 0.0001 (math.min self.line-height inner-height))
              inner-height))
        (local caret-position (+ position (rotation:rotate (glm.vec3 x-offset caret-y 0))))
        (set self.caret.layout.size (glm.vec3 (caret-width-for-mode self) caret-height size.z))
        (set self.caret.layout.position caret-position)
        (set self.caret.layout.rotation rotation)
        (set self.caret.layout.depth-offset-index caret-depth)
        (set self.caret.layout.clip-region clip)
        (when mark-layout-dirty?
          (self.caret.layout:mark-layout-dirty))))

    (fn update-placeholder [self opts]
      (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? true))
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? false))
      (if (> (length self.codepoints) 0)
          (self.placeholder:set-text ""
                                     {:mark-measure-dirty? mark-measure-dirty?
                                      })
          (self.placeholder:set-text placeholder-text
                                     {:mark-measure-dirty? mark-measure-dirty?
                                      })))

    (fn sync-from-model [self]
      (set self.codepoints model.codepoints)
      (set self.cursor-index model.cursor-index)
      (set self.mode model.mode)
      (set self.connected? model.connected?)
      (sync-viewport-state self))

    (fn apply-text-change [self notify? opts]
      (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? true))
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (sync-from-model self)
      (mark-virtual-dirty self {:mark-measure-dirty? mark-measure-dirty?})
      (update-placeholder self {:mark-measure-dirty? mark-measure-dirty?})
      (when (and mark-measure-dirty? self.layout)
        (self.layout:mark-measure-dirty))
      (self:update-caret-visual {:mark-layout-dirty? mark-layout-dirty?})
      (update-caret-layout self {:mark-layout-dirty? mark-layout-dirty?})
      (refresh-virtual-text self true)
      (when (and notify? options.on-change)
        (options.on-change self (self:get-text))))

    (fn apply-caret-change [self opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? false))
      (local prev-scroll-line (or (and self.scroll self.scroll.line) 0))
      (local prev-scroll-column (or (and self.scroll self.scroll.column) 0))
      (local prev-cursor-line (or self.cursor-line 0))
      (local prev-cursor-column (or self.cursor-column 0))
      (local prev-cursor-index (or self.cursor-index 0))
      (sync-from-model self)
      (local scroll-changed?
        (or (not (= prev-scroll-line self.scroll.line))
            (not (= prev-scroll-column self.scroll.column))))
      (local caret-moved?
        (or (not (= prev-cursor-line self.cursor-line))
            (not (= prev-cursor-column self.cursor-column))
            (not (= prev-cursor-index self.cursor-index))))
      (when scroll-changed?
        (mark-virtual-dirty self {:mark-measure-dirty? mark-measure-dirty?})
        (refresh-virtual-text self true)
        (when self.text.layout
          (self.text.layout:mark-layout-dirty)))
      (self:update-caret-visual {:mark-layout-dirty? mark-layout-dirty?})
      (when (or caret-moved? scroll-changed? mark-layout-dirty?)
        (update-caret-layout self {:mark-layout-dirty? mark-layout-dirty?})))

    (fn apply-mode-change [self opts]
      (apply-caret-change self opts))

    (fn update-caret-visual [self opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (when self.caret
        (self.caret:set-visible (and self.focused? true)
                                {:mark-layout-dirty? mark-layout-dirty?})
        (set self.caret.color
             (if (= self.mode :insert)
                 self.colors.caret-insert
                 self.colors.caret-normal))
        (when (and mark-layout-dirty? self.caret.layout)
          (self.caret.layout:mark-layout-dirty))))

    (fn update-focus-visual [self opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (local overlay self.focus-overlay)
      (when overlay
        (overlay:set-visible self.focused? {:mark-layout-dirty? mark-layout-dirty?}))
      (self:update-caret-visual {:mark-layout-dirty? mark-layout-dirty?})
      (self:update-background {:mark-layout-dirty? mark-layout-dirty?}))

    (fn update-background [self opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (local rect self.background)
      (when rect
        (local color
          (if self.focused?
              self.colors.focused-background
              (if self.hovered?
                  self.colors.hover-background
                  self.colors.background)))
        (set rect.color color)
        (when (and mark-layout-dirty? rect.layout)
          (rect.layout:mark-layout-dirty))))

    (fn sync-placeholder [self]
      (update-placeholder self))

    (fn measure-input [self layout]
      (refresh-virtual-text self)
      (self.text.layout:measurer)
      (self.placeholder.layout:measurer)
      (local text-measure self.text.layout.measure)
      (local placeholder-measure self.placeholder.layout.measure)
      (local min-column-width (* self.column-width self.min-columns))
      (local min-line-height (* self.line-height self.min-lines))
      (local inner-width (math.max (or options.content-min-width 0)
                                   text-measure.x
                                   placeholder-measure.x
                                   min-column-width))
      (local inner-height (math.max text-measure.y
                                    placeholder-measure.y
                                    min-line-height))
      (set self.content-size (glm.vec3 inner-width inner-height 0))
      (local total-width (+ (* 2 padding.x) inner-width))
      (local total-height (+ (* 2 padding.y) inner-height))
      (local clamped-width (math.max min-width total-width))
      (local clamped-height (math.max min-height total-height))
      (set layout.measure (glm.vec3 clamped-width clamped-height 0)))

    (fn layouter-input [self layout]
      (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
      (local position (or layout.position (glm.vec3 0 0 0)))
      (local clip layout.clip-region)
      (local depth-index (or layout.depth-offset-index 0))
      (local size (or layout.size layout.measure))
      (local inner-width (math.max 0 (- size.x (* 2 padding.x))))
      (local inner-height (math.max 0 (- size.y (* 2 padding.y))))
      (local inner-size (glm.vec3 inner-width inner-height size.z))
      (set self.inner-size inner-size)
      (apply-viewport self inner-size)
      (refresh-virtual-text self)
      (fn apply-layout [node depth]
        (when node
          (set node.layout.size size)
          (set node.layout.position position)
          (set node.layout.rotation rotation)
          (set node.layout.depth-offset-index (+ depth-index depth))
          (set node.layout.clip-region clip)
          (node.layout:layouter)))
      (apply-layout self.focus-overlay 0)
      (apply-layout self.background 1)
      (local text-offset (rotation:rotate (glm.vec3 padding.x padding.y 0)))
      (local text-position (+ position text-offset))
      (set self.text.layout.size inner-size)
      (set self.text.layout.position text-position)
      (set self.text.layout.rotation rotation)
      (set self.text.layout.depth-offset-index (+ depth-index 3))
      (set self.text.layout.clip-region clip)
      (self.text.layout:layouter)
      (set self.placeholder.layout.size inner-size)
      (set self.placeholder.layout.position text-position)
      (set self.placeholder.layout.rotation rotation)
      (set self.placeholder.layout.depth-offset-index (+ depth-index 4))
      (set self.placeholder.layout.clip-region clip)
      (self.placeholder.layout:layouter)
      (when self.caret
        (local caret-depth (+ depth-index 2))
        (local prefix (self:cursor-prefix-width))
        (local x-offset (+ padding.x prefix))
        (local caret-y (caret-vertical-offset self))
        (local caret-height
          (if self.multiline?
              (math.max 0.0001 (math.min self.line-height inner-height))
              inner-height))
        (local caret-position (+ position (rotation:rotate (glm.vec3 x-offset caret-y 0))))
        (set self.caret.layout.size (glm.vec3 (caret-width-for-mode self) caret-height size.z))
        (set self.caret.layout.position caret-position)
        (set self.caret.layout.rotation rotation)
        (set self.caret.layout.depth-offset-index caret-depth)
        (set self.caret.layout.clip-region clip)
        (self.caret.layout:layouter)))

    (fn connect-to-state [self]
      (when (and (not self.connected?) InputState)
        (InputState.connect-input self)
        (set self.connected? true)))

    (fn disconnect-from-state [self]
      (when (and self.connected? InputState)
        (InputState.disconnect-input self)
        (set self.connected? false)))

    (set layout
         (Layout {:name (or options.name "input")
                  :measurer (fn [layout-self]
                              (measure-input input layout-self))
                  :layouter (fn [layout-self]
                              (layouter-input input layout-self))
                  :children [focus-outline.layout
                             background.layout
                             text.layout
                             placeholder.layout
                             caret.layout]}))
    (when (and focus-node focus-context layout)
      (focus-context:attach-bounds focus-node {:layout layout}))

    (set input
         {:layout layout
          :model model
          :text text
          :placeholder placeholder
          :focus-overlay focus-outline
          :background background
          :caret caret
          :padding padding
          :caret-width caret-width
          :multiline? multiline?
          :focus-node focus-node
          :focus-manager focus-manager
          :mode model.mode
          :hovered? false
          :focused? false
          :connected? model.connected?
          :codepoints model.codepoints
          :cursor-index model.cursor-index
          :cursor-line 0
          :cursor-column 0
          :lines []
          :scroll {:line 0 :column 0}
          :visible-line-count initial-visible-lines
          :visible-column-count initial-visible-columns
          :explicit-line-count explicit-line-count
          :explicit-column-count explicit-column-count
          :min-lines resolved-min-lines
          :max-lines resolved-max-lines
          :min-columns resolved-min-columns
          :max-columns resolved-max-columns
          :line-height computed-line-height
          :column-width computed-column-width
          :virtual-dirty? true
          :colors colors
          :pointer-target pointer-target
          :changed model.changed})

    (set input.get-text
         (fn [_self]
           (model:get-text)))

    (set input.set-text
         (fn [_self value opts]
           (model:set-text value opts)))

    (set input.insert-text
         (fn [_self value]
           (model:insert-text value)))

    (set input.delete-at-cursor
         (fn [_self]
           (model:delete-at-cursor)))

    (set input.delete-before-cursor
         (fn [_self]
           (model:delete-before-cursor)))

    (set input.move-caret
         (fn [self delta]
           (local moved (model:move-caret delta))
           (when moved
             (apply-caret-change self))
           moved))

    (set input.move-caret-to
         (fn [self position]
           (local moved (model:move-caret-to position))
           (when moved
             (apply-caret-change self))
           moved))

    (set input.enter-insert-mode
         (fn [_self]
           (model:enter-insert-mode)))

    (set input.enter-normal-mode
         (fn [_self]
           (model:enter-normal-mode)))

    (set input.set-mode
         (fn [_self mode]
           (model:set-mode mode)))

    (set input.update-background update-background)
    (set input.update-caret-visual update-caret-visual)
    (set input.update-focus-visual update-focus-visual)
    (set input.sync-placeholder sync-placeholder)
    (set input.cursor-prefix-width cursor-prefix-width)
    (set input.caret-width-for-mode caret-width-for-mode)
    (set input.scroll-lines
         (fn [self delta]
           (if (self.model:scroll-lines delta)
               (do
                 (sync-viewport-state self)
                 (mark-virtual-dirty self)
                 (refresh-virtual-text self true)
                 true)
               false)))
    (set input.scroll-columns
         (fn [self delta]
           (if (self.model:scroll-columns delta)
               (do
                 (sync-viewport-state self)
                 (mark-virtual-dirty self)
                 (refresh-virtual-text self true)
                 true)
               false)))
    (set input.set-scroll-position
         (fn [self opts]
           (if (self.model:set-scroll-position (or opts {}))
               (do
                 (sync-viewport-state self)
                 (mark-virtual-dirty self)
                 (refresh-virtual-text self true)
                 true)
               false)))
    (set input.refresh-virtual-text
         (fn [self]
           (refresh-virtual-text self true)))

    (set input.request-focus
         (fn [self]
           (when self.focus-node
             (self.focus-node:request-focus))))

    (set input.on-click
         (fn [self _event]
           (self:request-focus)))

    (fn strip-single-trailing-newline [value]
      (if (not (= (type value) :string))
          (or value "")
          (let [n (# value)]
            (if (<= n 0)
                value
                (let [last (string.sub value n n)]
                  (if (= last "\n")
                      (let [without-nl (string.sub value 1 (- n 1))
                            m (# without-nl)]
                        (if (and (> m 0) (= (string.sub without-nl m m) "\r"))
                            (string.sub without-nl 1 (- m 1))
                            without-nl))
                      (if (= last "\r")
                          (string.sub value 1 (- n 1))
                          value)))))))

    (set input.on-double-click
         (fn [self _event]
           (ExternalEditor.edit-string
             (self:get-text)
             (fn [value]
               (when (not self.__dropped)
                 (local next-value (if self.multiline? value (strip-single-trailing-newline value)))
                 (self:set-text next-value)))
             options.external-editor)))

    (set input.on-hovered
         (fn [self hovered?]
           (set self.hovered? hovered?)
           (when system-cursors
             (system-cursors:set-cursor (if hovered? "ibeam" "arrow")))
           (self:update-background)))

    (fn resolve-context-actions [self event]
      (local config options.context-menu)
      (if (not config)
          (standard-context-menu self event)
          (if (= (type config) :function)
              (config self event)
              (error "Input context menu must be a function"))))

    (set input.on-right-click
         (fn [self event]
           (assert menu-manager "Input context menu requires a menu manager")
           (assert (and event event.point) "Input context menu requires event.point")
           (local actions (resolve-context-actions self event))
           (menu-manager:open {:actions actions
                               :position event.point
                               :open-button (and event event.button)})))

    (set input.on-state-connected
         (fn [self event]
           (model:on-state-connected event)
           (sync-from-model self)))

    (set input.on-state-disconnected
         (fn [self event]
           (model:on-state-disconnected event)
           (apply-mode-change self)))

    (set input.intersect
         (fn [self ray]
           (self.layout:intersect ray)))

    (clickables:register input)
    (clickables:register-right-click input)
    (clickables:register-double-click input)

    (hoverables:register input)

    (fn handle-focus [self]
      (when (not self.focused?)
        (set self.focused? true)
        (self:enter-normal-mode)
        (connect-to-state self)
        (when (not (= (current-state-name) :text))
          (set-state :text))
        (self:update-focus-visual)))

    (fn handle-blur [self]
      (when self.focused?
        (set self.focused? false)
        (disconnect-from-state self)
        (when (and InputState
                   InputState.active-input
                   InputState.release-active-input
                   (= (InputState.active-input) self))
          (InputState.release-active-input))
        (when (or (= (current-state-name) :text)
                  (= (current-state-name) :insert))
          (set-state :normal))
        (self:enter-normal-mode)
        (self:update-focus-visual)))

    (when focus-manager
      (set input.__focus-listener
           (focus-manager.focus-focus.connect
             (fn [event]
               (local node input.focus-node)
               (when (and node event (= event.current node))
                 (handle-focus input)))))
      (set input.__blur-listener
           (focus-manager.focus-blur.connect
             (fn [event]
               (local node input.focus-node)
               (when (and node event (= event.previous node))
                 (handle-blur input))))))
    (when (and focus-manager input.focus-node (= (focus-manager:get-focused-node) input.focus-node))
      (handle-focus input))

    (set input.__model-changed
         (model.changed:connect
           (fn [_text]
             (apply-text-change input true))))

    (set input.__mode-changed
         (model.mode-changed:connect
           (fn [_mode]
             (apply-mode-change input))))

    (apply-text-change input false {:mark-measure-dirty? false :mark-layout-dirty? false})
    (input:update-background {:mark-layout-dirty? false})

    (set input.on-text-input
         (fn [_self payload]
           (model:on-text-input payload)))

    (set input.on-key-up
         (fn [_self payload]
           (model:on-key-up payload)))

    (set input.drop
         (fn [self]
           (set self.__dropped true)
           (disconnect-from-state self)
           (clickables:unregister self)
           (clickables:unregister-right-click self)
           (clickables:unregister-double-click self)
           (hoverables:unregister self)
            (when self.__model-changed
              (self.model.changed:disconnect self.__model-changed true)
              (set self.__model-changed nil))
            (when self.__mode-changed
             (self.model.mode-changed:disconnect self.__mode-changed true)
             (set self.__mode-changed nil))
           (self.model:drop)
           (when self.__focus-listener
             (local manager self.focus-manager)
             (when (and manager manager.focus-focus)
               (manager.focus-focus.disconnect self.__focus-listener true))
             (set self.__focus-listener nil))
           (when self.__blur-listener
             (local manager self.focus-manager)
             (when (and manager manager.focus-blur)
               (manager.focus-blur.disconnect self.__blur-listener true))
             (set self.__blur-listener nil))
           (when self.focus-node
             (self.focus-node:drop)
             (set self.focus-node nil))
           (self.text:drop)
           (self.placeholder:drop)
           (self.focus-overlay:drop)
           (self.background:drop)
           (self.caret:drop)
           (self.layout:drop)))

    input))

(local InputModule {:Input Input
                    :standard-context-menu standard-context-menu})

(setmetatable InputModule
              {:__call (fn [_ opts]
                         (Input opts))})

InputModule

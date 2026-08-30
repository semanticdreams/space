(local glm (require :glm))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Rectangle (require :rectangle))
(local {: Layout : resolve-mark-flag} (require :layout))
(local gl (require :gl))
(local Modifiers (require :input-modifiers))
(local InputState (require :input-state-router))
(local {: fallback-glyph : line-height} (require :text-utils))
(local {: resolve-input-colors : resolve-padding} (require :widget-theme-utils))

(local KEY_BACKSPACE 8)
(local KEY_DELETE 127)
(local KEY_RETURN 13)
(local KEY_LEFT 1073741904)
(local KEY_RIGHT 1073741903)
(local KEY_DOWN 1073741905)
(local KEY_UP 1073741906)
(local KEY_HOME 1073741898)
(local KEY_END 1073741901)
(local KEY_PAGEUP 1073741899)
(local KEY_PAGEDOWN 1073741902)

(fn clip-codepoints [items max-count]
  (assert (= (type max-count) :number) "clip-codepoints requires max-count")
  (local out [])
  (local limit (math.max 0 (or max-count 0)))
  (var i 1)
  (while (and (<= i (length (or items []))) (<= i limit))
    (table.insert out (. items i))
    (set i (+ i 1)))
  out)

(fn byte-for-column [row column]
  (assert row "byte-for-column requires row")
  (local offsets (or row.column-byte-offsets [0]))
  (local idx (+ (math.max 0 (math.floor (or column 0))) 1))
  (local offset (. offsets idx))
  (if (= offset nil)
      (or row.end-byte row.line-end-byte row.start-byte 0)
      (+ (or row.start-byte 0) offset)))

(fn column-for-x [input row local-x]
  (assert input "column-for-x requires input")
  (local raw-column (if (> input.column-width 0)
                      (math.floor (/ (math.max 0 local-x) input.column-width))
                      0))
  (math.max 0 (math.min raw-column (length (or row.codepoints [])))))

(fn row-visible-column-count [input row]
  (assert row "row-visible-column-count requires row")
  (math.min input.column-count (length (or row.codepoints []))))

(fn mark-row-layouts-dirty [input]
  (each [_ row-widget (ipairs input.rows)]
    (when (and row-widget row-widget.layout)
      (row-widget.layout:mark-layout-dirty))))

(fn mark-caret-dirty [input]
  (when (and input.caret input.caret.layout)
    (input.caret.layout:mark-layout-dirty)))

(fn mark-viewport-dirty [input]
  (mark-row-layouts-dirty input)
  (mark-caret-dirty input))

(fn refresh-viewport [self opts]
  (assert self.buffer "refresh-viewport requires buffer")
  (local options (or opts {}))
  (local snapshot (self.buffer:get-viewport {:line self.scroll-line
                                             :column self.scroll-column
                                             :lines self.line-count
                                             :columns self.column-count}))
  (set self.viewport snapshot)
  (set self.scroll-line snapshot.start-line)
  (set self.scroll-column snapshot.start-column)
  (each [i row-widget (ipairs self.rows)]
    (local viewport-row (. snapshot.rows i))
    (local codepoints (clip-codepoints (and viewport-row viewport-row.codepoints)
                                       self.column-count))
    (row-widget:set-codepoints codepoints {:mark-measure-dirty? false}))
  (when (resolve-mark-flag options :mark-layout-dirty? true)
    (mark-viewport-dirty self))
  snapshot)

(fn sync-scroll [self]
  (assert self "sync-scroll requires input")
  (set self.scroll-line (math.max 0 (or self.buffer.scroll-line self.scroll-line 0))))

(fn notify-change [self]
  (when self.on-change
    (self.on-change self self.buffer)))

(fn ensure-viewport [self]
  (assert self "ensure-viewport requires input")
  (or self.viewport (self:refresh-viewport {:mark-layout-dirty? false})))

(fn caret-row [self]
  (assert self "caret-row requires input")
  (local viewport (ensure-viewport self))
  (var found nil)
  (each [_ row (ipairs (or viewport.rows []))]
    (when (and (not found)
               (>= (or self.buffer.cursor-byte 0) (or row.start-byte 0))
               (<= (or self.buffer.cursor-byte 0) (or row.line-end-byte row.end-byte 0)))
      (set found row)))
  found)

(fn line-from-cursor [self]
  (assert self "line-from-cursor requires input")
  (local viewport (ensure-viewport self))
  (var found-line nil)
  (each [_ row (ipairs (or viewport.rows []))]
    (when (and (not found-line)
               (>= (or self.buffer.cursor-byte 0) (or row.start-byte 0))
               (<= (or self.buffer.cursor-byte 0) (or row.line-end-byte row.end-byte 0)))
      (set found-line row.line)))
  found-line)

(fn keep-line-visible [self line]
  (when line
    (local next-scroll
      (if (< line self.scroll-line)
          line
          (>= line (+ self.scroll-line self.line-count))
          (math.max 0 (- line (- self.line-count 1)))
          self.scroll-line))
    (when (not (= next-scroll self.scroll-line))
      (set self.scroll-line next-scroll)
      (set self.buffer.scroll-line next-scroll))))

(fn infer-line-from-viewport-edge [self]
  (assert self "infer-line-from-viewport-edge requires input")
  (local viewport (ensure-viewport self))
  (local rows (or viewport.rows []))
  (local first-row (. rows 1))
  (local last-row (. rows (length rows)))
  (local cursor (or self.buffer.cursor-byte 0))
  (if (and first-row (< cursor (or first-row.start-byte 0)))
      (math.max 0 (- first-row.line 1))
      (and last-row (> cursor (or last-row.line-end-byte last-row.end-byte 0)))
      (+ last-row.line 1)
      nil))

(fn line-after-caret-move [self explicit-line]
  (assert self "line-after-caret-move requires input")
  (or explicit-line (line-from-cursor self) (infer-line-from-viewport-edge self)))

(fn caret-line-column [self]
  (assert self "caret-line-column requires input")
  (local row (caret-row self))
  (local cursor (or self.buffer.cursor-byte 0))
  (var column 0)
  (when row
    (each [i offset (ipairs (or row.column-byte-offsets []))]
      (when (<= (+ (or row.start-byte 0) offset) cursor)
        (set column (- i 1)))))
  (if row
      (values row.line column row)
      (values nil nil nil)))

(fn apply-caret-byte [self target-byte extend-selection?]
  (assert (= (type target-byte) :number) "apply-caret-byte requires numeric target")
  (local anchor (or self.selection-anchor-byte self.buffer.cursor-byte 0))
  (local moved (self.buffer:move-caret-to-byte target-byte))
  (if extend-selection?
      (do
        (set self.selection-anchor-byte anchor)
        (self.buffer:set-selection anchor self.buffer.cursor-byte))
      (do
        (set self.selection-anchor-byte self.buffer.cursor-byte)
        (when self.buffer.selection
          (self.buffer:clear-selection))))
  (when moved
    (keep-line-visible self (line-after-caret-move self nil))
    (mark-caret-dirty self)
    (self:refresh-viewport))
  moved)

(fn apply-caret-line-column [self line column extend-selection?]
  (assert (= (type line) :number) "apply-caret-line-column requires line")
  (local anchor (or self.selection-anchor-byte self.buffer.cursor-byte 0))
  (local moved (self.buffer:move-caret-to-line-column (math.max 0 line) (math.max 0 column)))
  (if extend-selection?
      (do
        (set self.selection-anchor-byte anchor)
        (self.buffer:set-selection anchor self.buffer.cursor-byte))
      (do
        (set self.selection-anchor-byte self.buffer.cursor-byte)
        (when self.buffer.selection
          (self.buffer:clear-selection))))
  (when moved
    (keep-line-visible self (line-after-caret-move self line))
    (mark-caret-dirty self)
    (self:refresh-viewport))
  moved)

(fn insert-text [self text]
  (assert (= (type text) :string) "VirtualInput insert-text requires string text")
  (when self.buffer.selection
    (if self.buffer.delete-selection
        (self.buffer:delete-selection)
        (error "VirtualInput requires buffer:delete-selection for selected insertion")))
  (local changed (self.buffer:insert-text text))
  (when changed
    (set self.selection-anchor-byte self.buffer.cursor-byte)
    (notify-change self)
    (self:refresh-viewport))
  changed)

(fn delete-active-selection [self]
  (when (not self.buffer.delete-selection)
    (error "VirtualInput requires buffer:delete-selection for selected delete"))
  (local changed (self.buffer:delete-selection))
  (when changed
    (set self.selection-anchor-byte self.buffer.cursor-byte)
    (notify-change self)
    (self:refresh-viewport))
  changed)

(fn delete-before-cursor [self]
  (if self.buffer.selection
      (delete-active-selection self)
      (do
        (local changed (self.buffer:delete-before-cursor))
        (when changed
          (set self.selection-anchor-byte self.buffer.cursor-byte)
          (notify-change self)
          (self:refresh-viewport))
        changed)))

(fn delete-at-cursor [self]
  (if self.buffer.selection
      (delete-active-selection self)
      (do
        (local changed (self.buffer:delete-at-cursor))
        (when changed
          (set self.selection-anchor-byte self.buffer.cursor-byte)
          (notify-change self)
          (self:refresh-viewport))
        changed)))

(fn update-horizontal-selection [self anchor extend-selection?]
  (if extend-selection?
      (do
        (set self.selection-anchor-byte anchor)
        (self.buffer:set-selection anchor self.buffer.cursor-byte))
      (do
        (set self.selection-anchor-byte self.buffer.cursor-byte)
        (when self.buffer.selection
          (self.buffer:clear-selection)))))

(fn apply-horizontal-caret-move [self delta extend-selection?]
  (when (not self.buffer.move-caret-horizontal)
    (error "VirtualInput requires buffer:move-caret-horizontal for horizontal movement"))
  (local anchor (or self.selection-anchor-byte self.buffer.cursor-byte 0))
  (local moved (self.buffer:move-caret-horizontal delta))
  (update-horizontal-selection self anchor extend-selection?)
  (when moved
    (keep-line-visible self (line-after-caret-move self nil))
    (mark-caret-dirty self)
    (self:refresh-viewport))
  moved)

(fn move-caret [self delta opts]
  (local (line column _row) (caret-line-column self))
  (local extend? (and opts opts.extend-selection?))
  (if (= delta :left)
      (apply-horizontal-caret-move self -1 extend?)
      (= delta :right)
      (apply-horizontal-caret-move self 1 extend?)
      (= delta :up)
      (apply-caret-line-column self (- line 1) column extend?)
      (= delta :down)
      (apply-caret-line-column self (+ line 1) column extend?)
      (= delta :home)
      (apply-caret-line-column self line 0 extend?)
      (= delta :end)
      (apply-caret-line-column self line (row-visible-column-count self _row) extend?)
      (error (.. "VirtualInput unsupported caret move: " (tostring delta)))))

(fn scroll-lines [self delta]
  (local changed (self.buffer:scroll-lines delta))
  (when changed
    (sync-scroll self)
    (self:refresh-viewport)
    (when (not (caret-row self))
      (apply-caret-line-column self self.scroll-line 0 false)))
  changed)

(fn copy-selection [self]
  (if self.buffer.selection
      (do
        (local text (self.buffer:get-selected-text))
        (gl.clipboard-set text)
        text)
      false))

(fn save [self]
  (local result (self.buffer:save))
  (when self.on-save
    (self.on-save self result))
  result)

(fn on-text-input [self payload]
  (if (and payload (= (type payload.text) :string))
      (self:insert-text payload.text)
      false))

(fn on-key-down [self payload]
  (if (not (and payload payload.key))
      false
      (do
        (local key payload.key)
        (local ctrl? (Modifiers.ctrl-held? payload.mod))
        (local shift? (Modifiers.shift-held? payload.mod))
        (if (and ctrl? (= key (string.byte "s")))
            (do (self:save) true)
            (and ctrl? (= key (string.byte "S")))
            (do (self:save) true)
            (and ctrl? (= key (string.byte "c")))
            (if (self:copy-selection) true false)
            (and ctrl? (= key (string.byte "C")))
            (if (self:copy-selection) true false)
            (= key KEY_LEFT)
            (self:move-caret :left {:extend-selection? shift?})
            (= key KEY_RIGHT)
            (self:move-caret :right {:extend-selection? shift?})
            (= key KEY_UP)
            (self:move-caret :up {:extend-selection? shift?})
            (= key KEY_DOWN)
            (self:move-caret :down {:extend-selection? shift?})
            (= key KEY_HOME)
            (self:move-caret :home {:extend-selection? shift?})
            (= key KEY_END)
            (self:move-caret :end {:extend-selection? shift?})
            (= key KEY_PAGEUP)
            (self:scroll-lines (- self.line-count))
            (= key KEY_PAGEDOWN)
            (self:scroll-lines self.line-count)
            (= key KEY_BACKSPACE)
            (self:delete-before-cursor)
            (= key KEY_DELETE)
            (self:delete-at-cursor)
            (= key KEY_RETURN)
            (self:insert-text "\n")
            false))))

(fn local-point-from-event [self event]
  (if (and event event.local-point)
      event.local-point
      (if (and event event.point self.layout)
          (- event.point self.layout.position)
          (glm.vec3 0 0 0))))

(fn on-click [self event]
  (self:request-focus)
  (local point (local-point-from-event self event))
  (local row-index (if (and event event.row-index)
                     event.row-index
                     (+ 1 (math.floor (/ (math.max 0 (- point.y self.padding.y)) self.line-height)))))
  (local viewport (ensure-viewport self))
  (local row (. viewport.rows row-index))
  (when row
    (local column (if (and event event.column)
                    event.column
                    (column-for-x self row (- point.x self.padding.x))))
    (apply-caret-byte self (byte-for-column row column) (and event (Modifiers.shift-held? event.mod))))
  true)

(fn measure-virtual-input [input layout]
  (each [_ row-widget (ipairs input.rows)]
    (row-widget.layout:measurer))
  (local width (+ (* 2 input.padding.x) (* input.column-width input.column-count)))
  (local height (+ (* 2 input.padding.y) (* input.line-height input.line-count)))
  (set layout.measure (glm.vec3 width height 0)))

(fn layout-child [child position rotation size depth clip]
  (set child.layout.position position)
  (set child.layout.rotation rotation)
  (set child.layout.size size)
  (set child.layout.depth-offset-index depth)
  (set child.layout.clip-region clip)
  (child.layout:layouter))

(fn caret-position [input position rotation line column]
  (local visible-row (+ (- line input.scroll-line) 1))
  (+ position
     (rotation:rotate (glm.vec3 (+ input.padding.x (* (- column input.scroll-column) input.column-width))
                                 (+ input.padding.y (* (- visible-row 1) input.line-height))
                                 0))))

(fn show-caret [input position rotation size depth clip line column]
  (set input.caret.visible? true)
  (layout-child input.caret
                (caret-position input position rotation line column)
                rotation
                (glm.vec3 input.caret-width input.line-height size.z)
                depth
                clip))

(fn hide-caret [input position rotation size depth clip]
  (set input.caret.visible? false)
  (layout-child input.caret position rotation (glm.vec3 0 0 size.z) depth clip))

(fn layout-caret [input position rotation size depth clip]
  (local (line column row) (caret-line-column input))
  (if row
      (show-caret input position rotation size depth clip line column)
      (hide-caret input position rotation size depth clip)))

(fn layout-virtual-input [input layout]
  (assert input "layout-virtual-input requires input")
  (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
  (local position (or layout.position (glm.vec3 0 0 0)))
  (local size (or layout.size layout.measure))
  (local clip layout.clip-region)
  (local depth (or layout.depth-offset-index 0))
  (input:refresh-viewport {:mark-layout-dirty? false})
  (layout-child input.background position rotation size (+ depth 1) clip)
  (each [i row-widget (ipairs input.rows)]
    (local row-pos (+ position (rotation:rotate (glm.vec3 input.padding.x
                                                          (+ input.padding.y (* (- i 1) input.line-height))
                                                          0))))
    (layout-child row-widget row-pos rotation (glm.vec3 (- size.x (* 2 input.padding.x)) input.line-height size.z) (+ depth 3) clip))
  (layout-caret input position rotation size (+ depth 2) clip))

(fn measure-layout [layout]
  (measure-virtual-input layout.virtual-input layout))

(fn run-layout [layout]
  (layout-virtual-input layout.virtual-input layout))

(fn intersect-virtual-input [self ray]
  (self.layout:intersect ray))

(fn request-focus [self]
  (when self.focus-node
    (self.focus-node:request-focus))
  (when (and InputState (not self.connected?))
    (InputState.connect-input self)
    (InputState.set-state :text))
  true)

(fn on-state-connected [self _event]
  (set self.connected? true))

(fn on-state-disconnected [self _event]
  (set self.connected? false))

(fn handle-focus [input]
  (input:request-focus))

(fn handle-blur [input]
  (when input.connected?
    (InputState.disconnect-input input)))

(fn focus-event-current? [input event]
  (= (and event event.current) input.focus-node))

(fn focus-event-previous? [input event]
  (= (and event event.previous) input.focus-node))

(fn make-focus-listener [input]
  (fn [event]
    (when (focus-event-current? input event)
      (handle-focus input))))

(fn make-blur-listener [input]
  (fn [event]
    (when (focus-event-previous? input event)
      (handle-blur input))))

(fn drop [self]
  (assert (not self.__dropped) "VirtualInput dropped twice")
  (set self.__dropped true)
  (self.clickables:unregister self)
  (each [_ row-widget (ipairs self.rows)]
    (row-widget:drop))
  (self.background:drop)
  (self.caret:drop)
  (when self.focus-node
    (self.focus-node:drop)
    (set self.focus-node nil))
  (when (and self.connected? InputState)
    (InputState.disconnect-input self))
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
  (self.layout:drop))

(fn resolve-line-height* [text-style]
  (local value (line-height text-style))
  (if (and value (> value 0)) value 1.6))

(fn resolve-column-width* [text-style caret-width]
  (local font (and text-style text-style.font))
  (if font
      (do
        (local glyph (fallback-glyph font 32))
        (local advance (* glyph.advance text-style.scale))
        (if (and advance (> advance 0)) advance caret-width))
      caret-width))

(fn VirtualInput [opts]
  (local options (or opts {}))
  (local buffer (assert options.buffer "VirtualInput requires opts.buffer"))
  (local line-count (math.max 1 (math.floor (or options.line-count 24))))
  (local column-count (math.max 1 (math.floor (or options.column-count 80))))
  (local padding (resolve-padding options.padding))
  (local caret-width (or options.caret-width 0.05))
  (fn build [ctx]
    (assert ctx "VirtualInput requires ctx")
    (assert ctx.get-text-ssbo-batcher "VirtualInput requires ctx.get-text-ssbo-batcher")
    (assert ctx.get-rectangle-quad-batcher "VirtualInput requires ctx.get-rectangle-quad-batcher")
    (local clickables (assert ctx.clickables "VirtualInput requires ctx.clickables"))
    (local colors (resolve-input-colors ctx options))
    (local focus-context (and ctx ctx.focus))
    (local focusable? (and focus-context (not (= options.focusable? false))))
    (local focus-node
      (and focusable?
           (focus-context:create-node {:name (or options.focus-name
                                                  options.name
                                                  "virtual-input")})))
    (local focus-manager (and focus-node focus-node.manager))
    (local text-style (or options.text-style (TextStyle {:color colors.foreground})))
    (local row-widgets [])
    (for [_ 1 line-count]
      (table.insert row-widgets ((Text {:codepoints [] :style text-style}) ctx)))
    (local background ((Rectangle {:color colors.background}) ctx))
    (local caret ((Rectangle {:color colors.caret-insert}) ctx))
    (local computed-line-height (resolve-line-height* text-style))
    (local computed-column-width (resolve-column-width* text-style caret-width))
    (local child-layouts [background.layout caret.layout])
    (each [_ row-widget (ipairs row-widgets)]
      (table.insert child-layouts row-widget.layout))
    (local layout
      (Layout {:name (or options.name "virtual-input")
               :measurer measure-layout
               :layouter run-layout
               :children child-layouts}))
    (local input
      {:__dropped false
       :layout layout
       :buffer buffer
       :rows row-widgets
       :background background
       :caret caret
       :clickables clickables
       :focus-node focus-node
       :focus-manager focus-manager
       :connected? false
       :line-count line-count
       :column-count column-count
       :padding padding
       :line-height computed-line-height
       :column-width computed-column-width
       :caret-width caret-width
       :scroll-line (math.max 0 (or buffer.scroll-line 0))
       :scroll-column 0
       :viewport nil
       :selection-anchor-byte (or buffer.cursor-byte 0)
       :on-change options.on-change
       :on-save options.on-save
       :refresh-viewport refresh-viewport
       :insert-text insert-text
       :delete-before-cursor delete-before-cursor
       :delete-at-cursor delete-at-cursor
       :move-caret move-caret
       :scroll-lines scroll-lines
       :copy-selection copy-selection
       :save save
       :on-text-input on-text-input
       :on-key-down on-key-down
       :on-click on-click
       :request-focus request-focus
       :on-state-connected on-state-connected
       :on-state-disconnected on-state-disconnected
       :intersect intersect-virtual-input
       :drop drop})
    (set layout.virtual-input input)
    (when (and focus-node focus-context layout)
      (focus-context:attach-bounds focus-node {:layout layout}))
    (when focus-manager
      (set input.__focus-listener
           (focus-manager.focus-focus.connect (make-focus-listener input)))
      (set input.__blur-listener
           (focus-manager.focus-blur.connect (make-blur-listener input))))
    (clickables:register input)
    (input:refresh-viewport {:mark-layout-dirty? false})
    input))

VirtualInput

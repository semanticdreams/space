(local Signal (require :signal))
(local {: codepoints-from-text
        : copy-codepoints
        : line-break?
        : newline-codepoint
        : carriage-return-codepoint} (require :text-utils))

(fn codepoints->text [codepoints]
  (table.concat
    (icollect [_ codepoint (ipairs codepoints)]
              (utf8.char codepoint))))

(fn insert-codepoints! [target idx items]
  (var i 0)
  (each [_ codepoint (ipairs items)]
    (table.insert target (+ idx i) codepoint)
    (set i (+ i 1))))

(fn delete-at! [target idx]
  (if (and idx (> idx 0) (<= idx (length target)))
      (do
        (table.remove target idx)
        true)
      false))

(fn clamp-index [value limit]
  (math.max 0 (math.min value limit)))

(fn build-lines [codepoints]
  (local total (length codepoints))
  (var lines [])
  (var current [])
  (fn push-line [newline-length]
    (table.insert lines {:codepoints current
                         :newline-length (or newline-length 0)})
    (set current []))
  (var i 1)
  (while (<= i total)
    (local codepoint (. codepoints i))
    (if (line-break? codepoint)
        (do
          (var newline-length 1)
          (when (and (= codepoint carriage-return-codepoint)
                     (< i total)
                     (= (. codepoints (+ i 1)) newline-codepoint))
            (set newline-length 2)
            (set i (+ i 1)))
          (push-line newline-length))
        (table.insert current codepoint))
    (set i (+ i 1)))
  (push-line 0)
  lines)

(fn longest-line-length [lines]
  (var longest 0)
  (each [_ line (ipairs lines)]
    (when (and line line.codepoints)
      (set longest (math.max longest (length line.codepoints)))))
  longest)

(fn line-length [lines idx]
  (local line (. lines (+ idx 1)))
  (if (and line line.codepoints)
      (length line.codepoints)
      0))

(fn update-caret-coordinates! [self]
  (local cursor (or self.cursor-index 0))
  (var consumed 0)
  (var line-index 0)
  (var column 0)
  (var found? false)
  (var i 1)
  (local total (length self.lines))
  (while (<= i total)
    (local line (. self.lines i))
    (local len (or (and line (length line.codepoints)) 0))
    (local line-end (+ consumed len))
    (if (<= cursor line-end)
        (do
          (set line-index (- i 1))
          (set column (- cursor consumed))
          (set found? true)
          (set i (+ total 1)))
        (set consumed (+ line-end (or (and line line.newline-length) 0))))
    (set i (+ i 1)))
  (when (not found?)
    (set line-index (math.max 0 (- total 1)))
    (local last-line (. self.lines (math.max 1 total)))
    (local len (and last-line (length last-line.codepoints)))
    (set column (or len 0)))
  (set self.cursor-line (math.max 0 line-index))
  (set self.cursor-column (math.max 0 column)))

(fn ensure-scroll-visible! [self]
  (local viewport-lines (math.max 1 (or self.viewport-lines 1)))
  (local viewport-columns (math.max 1 (or self.viewport-columns 1)))
  (local total-lines (length self.lines))
  (local max-line-scroll (math.max 0 (- total-lines viewport-lines)))
  (set self.scroll-line (math.max 0 (math.min (or self.scroll-line 0) max-line-scroll)))
  (local caret-line (math.max 0 (or self.cursor-line 0)))
  (when (< caret-line self.scroll-line)
    (set self.scroll-line caret-line))
  (when (> caret-line (+ self.scroll-line (- viewport-lines 1)))
    (set self.scroll-line (math.max 0 (- caret-line (- viewport-lines 1)))))
  (set self.scroll-line (math.max 0 (math.min self.scroll-line max-line-scroll)))
  (local caret-column (math.max 0 (or self.cursor-column 0)))
  (local caret-line-length (line-length self.lines caret-line))
  (local longest (math.max caret-line-length (or self.longest-line-length 0)))
  (local max-column-scroll (math.max 0 (- longest viewport-columns)))
  (set self.scroll-column (math.max 0 (math.min (or self.scroll-column 0) max-column-scroll)))
  (when (< caret-column self.scroll-column)
    (set self.scroll-column caret-column))
  (when (>= caret-column (+ self.scroll-column viewport-columns))
    (set self.scroll-column
         (math.max 0 (- caret-column (- viewport-columns 1)))))
  (set self.scroll-column (math.max 0 (math.min self.scroll-column max-column-scroll))))

(fn refresh-derived-state! [self]
  (set self.lines (build-lines self.codepoints))
  (set self.longest-line-length (longest-line-length self.lines))
  (update-caret-coordinates! self)
  (ensure-scroll-visible! self))

(fn update-viewport-lines! [self count]
  (local sanitized (math.max 1 (math.floor (or count 1))))
  (if (= sanitized self.viewport-lines)
      false
      (do
        (set self.viewport-lines sanitized)
        (ensure-scroll-visible! self)
        true)))

(fn update-viewport-columns! [self count]
  (local sanitized (math.max 1 (math.floor (or count 1))))
  (if (= sanitized self.viewport-columns)
      false
      (do
        (set self.viewport-columns sanitized)
        (ensure-scroll-visible! self)
        true)))

(fn scroll-lines! [self delta]
  (if (= delta 0)
      false
      (let [viewport (math.max 1 self.viewport-lines)
            max-scroll (math.max 0 (- (length self.lines) viewport))
            next (math.max 0 (math.min (+ self.scroll-line delta) max-scroll))]
        (if (= next self.scroll-line)
            false
            (do
              (set self.scroll-line next)
              true)))))

(fn scroll-columns! [self delta]
  (if (= delta 0)
      false
      (let [viewport (math.max 1 self.viewport-columns)
            longest (math.max 0 self.longest-line-length)
            max-scroll (math.max 0 (- longest viewport))
            next (math.max 0 (math.min (+ self.scroll-column delta) max-scroll))]
        (if (= next self.scroll-column)
            false
            (do
              (set self.scroll-column next)
              true)))))

(fn set-scroll-position! [self opts]
  (local next-line (math.max 0 (math.floor (or opts.line self.scroll-line))))
  (local next-column (math.max 0 (math.floor (or opts.column self.scroll-column))))
  (var changed false)
  (local viewport-lines (math.max 1 self.viewport-lines))
  (local viewport-columns (math.max 1 self.viewport-columns))
  (local max-line-scroll (math.max 0 (- (length self.lines) viewport-lines)))
  (local max-column-scroll (math.max 0 (- self.longest-line-length viewport-columns)))
  (local clamped-line (math.max 0 (math.min next-line max-line-scroll)))
  (local clamped-column (math.max 0 (math.min next-column max-column-scroll)))
  (when (not (= clamped-line self.scroll-line))
    (set changed true)
    (set self.scroll-line clamped-line))
  (when (not (= clamped-column self.scroll-column))
    (set changed true)
    (set self.scroll-column clamped-column))
  changed)

(fn visible-codepoints [self]
  (local newline newline-codepoint)
  (var buffer [])
  (local viewport-lines (math.max 1 self.viewport-lines))
  (local viewport-columns (math.max 1 self.viewport-columns))
  (local total-lines (length self.lines))
  (for [offset 0 (- viewport-lines 1)]
    (when (> offset 0)
      (table.insert buffer newline))
    (local line-index (+ self.scroll-line offset))
    (when (< line-index total-lines)
      (local line (. self.lines (+ line-index 1)))
      (when (and line line.codepoints)
        (local start self.scroll-column)
        (local stop (+ start viewport-columns))
        (local limit (length line.codepoints))
        (var column start)
        (while (and (< column stop)
                    (< column limit))
          (local codepoint (. line.codepoints (+ column 1)))
          (when codepoint
            (table.insert buffer codepoint))
          (set column (+ column 1))))))
  buffer)

(fn InputModel [opts]
  (local options (or opts {}))
  (local initial-codepoints
    (copy-codepoints (codepoints-from-text (or options.text ""))))
  (local changed (Signal))
  (local mode-changed (Signal))
  (var model nil)

  (fn notify-changed [self]
    (self.changed:emit (self:get-text)))

  (fn notify-mode-changed [self]
    (self.mode-changed:emit self.mode))

  (fn set-codepoints [self items reset-cursor?]
    (set self.codepoints (copy-codepoints (or items [])))
    (if reset-cursor?
        (set self.cursor-index (length self.codepoints))
        (set self.cursor-index (clamp-index self.cursor-index (length self.codepoints))))
    (refresh-derived-state! self)
    (notify-changed self))

  (fn set-text [self value opts]
    (local options (or opts {}))
    (local reset-cursor? (not (= options.reset-cursor? false)))
    (set-codepoints self (codepoints-from-text (or value "")) reset-cursor?))

  (fn get-text [self]
    (codepoints->text self.codepoints))

  (fn insert-text [self value]
    (when (and value (> (string.len value) 0))
      (local codepoints (codepoints-from-text value))
      (set self.cursor-index (clamp-index self.cursor-index (length self.codepoints)))
      (insert-codepoints! self.codepoints (+ self.cursor-index 1) codepoints)
      (set self.cursor-index (+ self.cursor-index (length codepoints)))
      (refresh-derived-state! self)
      (notify-changed self)))

  (fn delete-before-cursor [self]
    (if (> self.cursor-index 0)
        (do
          (delete-at! self.codepoints self.cursor-index)
          (set self.cursor-index (- self.cursor-index 1))
          (refresh-derived-state! self)
          (notify-changed self)
          true)
        false))

  (fn delete-at-cursor [self]
    (local removed (delete-at! self.codepoints (+ self.cursor-index 1)))
    (when removed
      (refresh-derived-state! self)
      (notify-changed self))
    removed)

  (fn move-caret [self delta]
    (local next (clamp-index (+ self.cursor-index delta) (length self.codepoints)))
    (if (= next self.cursor-index)
        false
        (do
          (set self.cursor-index next)
          (update-caret-coordinates! self)
          (ensure-scroll-visible! self)
          true)))

  (fn move-caret-to [self position]
    (local next (clamp-index position (length self.codepoints)))
    (if (= next self.cursor-index)
        false
        (do
          (set self.cursor-index next)
          (update-caret-coordinates! self)
          (ensure-scroll-visible! self)
          true)))

  (fn set-mode [self mode]
    (when (not (= self.mode mode))
      (set self.mode mode)
      (notify-mode-changed self)))

  (fn enter-insert-mode [self]
    (set-mode self :insert))

  (fn enter-normal-mode [self]
    (set-mode self :normal))

  (fn on-text-input [self payload]
    (if (= self.mode :insert)
        (do
          (when (and payload payload.text)
            (self:insert-text payload.text))
          true)
        false))

  (fn on-key-up [_self _payload]
    false)

  (fn on-state-connected [self _event]
    (set self.connected? true))

  (fn on-state-disconnected [self _event]
    (set self.connected? false)
    (self:enter-normal-mode))

  (fn drop [self]
    (self.changed:clear)
    (self.mode-changed:clear))

  (set model
       {:codepoints initial-codepoints
        :cursor-index (length initial-codepoints)
        :mode :normal
        :connected? false
        :viewport-lines 1
        :viewport-columns 1
        :scroll-line 0
        :scroll-column 0
        :cursor-line 0
        :cursor-column 0
        :lines []
        :longest-line-length 0
        :changed changed
        :mode-changed mode-changed})

  (set model.get-text get-text)
  (set model.set-text set-text)
  (set model.insert-text insert-text)
  (set model.delete-at-cursor delete-at-cursor)
  (set model.delete-before-cursor delete-before-cursor)
  (set model.move-caret move-caret)
  (set model.move-caret-to move-caret-to)
  (set model.enter-insert-mode enter-insert-mode)
  (set model.enter-normal-mode enter-normal-mode)
  (set model.set-mode set-mode)
  (set model.on-text-input on-text-input)
  (set model.on-key-up on-key-up)
  (set model.on-state-connected on-state-connected)
  (set model.on-state-disconnected on-state-disconnected)
  (set model.set-codepoints set-codepoints)
  (set model.notify-changed notify-changed)
  (set model.drop drop)
  (set model.set-viewport-lines update-viewport-lines!)
  (set model.set-viewport-columns update-viewport-columns!)
  (set model.scroll-lines scroll-lines!)
  (set model.scroll-columns scroll-columns!)
  (set model.set-scroll-position set-scroll-position!)
  (set model.get-visible-codepoints visible-codepoints)

  (refresh-derived-state! model)

  model)

InputModel

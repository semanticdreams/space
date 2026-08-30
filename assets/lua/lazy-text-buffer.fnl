(local {: codepoints-from-text} (require :text-utils))
(local fs (require :fs))

(fn valid-utf8? [text]
  (local (ok _result) (pcall (fn [] (icollect [_ cp (utf8.codes text)] cp))))
  ok)

(fn byte-len [text]
  (# text))

(fn utf8-sequence-length [byte]
  (if (< byte 0x80)
      1
      (and (>= byte 0xC2) (< byte 0xE0))
      2
      (and (>= byte 0xE0) (< byte 0xF0))
      3
      (and (>= byte 0xF0) (< byte 0xF5))
      4
      nil))

(fn utf8-continuation? [byte]
  (and byte (>= byte 0x80) (< byte 0xC0)))

(fn complete-utf8-sequence-length-at [text index]
  (local seq-len (utf8-sequence-length (string.byte text index)))
  (local total (# text))
  (if (not seq-len)
      nil
      (> (+ index seq-len -1) total)
      nil
      (do
        (var valid true)
        (for [offset 1 (- seq-len 1)]
          (when (not (utf8-continuation? (string.byte text (+ index offset))))
            (set valid false)))
        (if valid seq-len nil))))

(fn complete-utf8-prefix-length [text]
  (var index 1)
  (var prefix-end 0)
  (local total (# text))
  (var scanning true)
  (while (and scanning (<= index total))
    (local seq-len (complete-utf8-sequence-length-at text index))
    (if seq-len
        (do
          (set prefix-end (+ index seq-len -1))
          (set index (+ index seq-len)))
        (set scanning false)))
  prefix-end)

(fn clamp [value low high]
  (math.max low (math.min high value)))

(fn make-piece [source offset bytes]
  {:source source :offset offset :bytes bytes})

(fn piece-text [piece buffer]
  (if (= piece.source :add)
      (string.sub buffer.add-buffer (+ piece.offset 1) (+ piece.offset piece.bytes))
      (do
        (local range (buffer.source:read-range piece.offset piece.bytes))
        range.bytes)))

(fn total-bytes [pieces]
  (var total 0)
  (each [_ piece (ipairs pieces)]
    (set total (+ total piece.bytes)))
  total)

(fn normalize-pieces [pieces]
  (local out [])
  (each [_ piece (ipairs pieces)]
    (when (> piece.bytes 0)
      (local prev (. out (# out)))
      (if (and prev
               (= prev.source piece.source)
               (= (+ prev.offset prev.bytes) piece.offset))
          (set prev.bytes (+ prev.bytes piece.bytes))
          (table.insert out (make-piece piece.source piece.offset piece.bytes)))))
  out)

(fn split-pieces-at [pieces byte]
  (local before [])
  (local after [])
  (var pos 0)
  (each [_ piece (ipairs pieces)]
    (local next-pos (+ pos piece.bytes))
    (if (<= next-pos byte)
        (table.insert before (make-piece piece.source piece.offset piece.bytes))
        (if (>= pos byte)
            (table.insert after (make-piece piece.source piece.offset piece.bytes))
            (do
              (local left-bytes (- byte pos))
              (local right-bytes (- piece.bytes left-bytes))
              (table.insert before (make-piece piece.source piece.offset left-bytes))
              (table.insert after (make-piece piece.source (+ piece.offset left-bytes) right-bytes)))))
    (set pos next-pos))
  (values (normalize-pieces before) (normalize-pieces after)))

(fn pieces-between [pieces start-byte end-byte]
  (local out [])
  (var pos 0)
  (each [_ piece (ipairs pieces)]
    (local next-pos (+ pos piece.bytes))
    (local start (math.max start-byte pos))
    (local finish (math.min end-byte next-pos))
    (when (> finish start)
      (table.insert out (make-piece piece.source (+ piece.offset (- start pos)) (- finish start))))
    (set pos next-pos))
  (normalize-pieces out))

(fn read-composed-range [buffer start-byte max-bytes]
  (local finish (math.min (+ start-byte max-bytes) buffer.size))
  (local parts [])
  (each [_ piece (ipairs (pieces-between buffer.pieces start-byte finish))]
    (table.insert parts (piece-text piece buffer)))
  (table.concat parts ""))

(fn byte-at [buffer byte]
  (when (< byte buffer.size)
    (local text (read-composed-range buffer byte 1))
    (when (> (# text) 0)
      (string.byte text 1))))

(fn nearest-anchor [anchors line]
  (var best (. anchors 1))
  (each [_ anchor (ipairs anchors)]
    (when (and (<= anchor.line line) (>= anchor.line best.line))
      (set best anchor)))
  best)

(fn find-line-start [buffer line]
  (if (<= line 0)
      0
      (do
        (local anchor (nearest-anchor buffer.line-anchors line))
        (var current-line anchor.line)
        (var pos anchor.byte)
        (while (and (< current-line line) (< pos buffer.size))
          (local chunk (read-composed-range buffer pos buffer.chunk-bytes))
          (var i 1)
          (var found false)
          (while (and (<= i (# chunk)) (< current-line line) (not found))
            (local b (string.byte chunk i))
            (if (= b 10)
                (do
                  (set current-line (+ current-line 1))
                  (set pos (+ pos i))
                  (table.insert buffer.line-anchors {:line current-line :byte pos})
                  (set found true))
                (= b 13)
                (do
                  (local next-b (if (< i (# chunk))
                                    (string.byte chunk (+ i 1))
                                    (byte-at buffer (+ pos i))))
                  (set current-line (+ current-line 1))
                  (if (= next-b 10)
                      (set pos (+ pos i 1))
                      (set pos (+ pos i)))
                  (table.insert buffer.line-anchors {:line current-line :byte pos})
                  (set found true)))
            (set i (+ i 1)))
          (when (not found)
            (set pos (+ pos (# chunk))))
          (when (= (# chunk) 0)
            (set current-line line)))
        pos)))

(fn clipped-row-values [text columns]
  (local prefix (string.sub text 1 (complete-utf8-prefix-length text)))
  (local offsets [0])
  (local cps [])
  (var out-end 0)
  (var count 0)
  (each [byte-index cp (utf8.codes prefix)]
    (when (< count columns)
      (table.insert cps cp)
      (set out-end (- (+ byte-index (byte-len (utf8.char cp))) 1))
      (table.insert offsets out-end)
      (set count (+ count 1))))
  (values (string.sub prefix 1 out-end) cps offsets))

(fn build-row [buffer line start-byte columns]
  (var pos start-byte)
  (var newline-bytes 0)
  (var end-byte start-byte)
  (var line-end-byte start-byte)
  (var line-end-known? false)
  (var partial? false)
  (local visible-parts [])
  (var visible-bytes 0)
  (var scanned-bytes 0)
  (local scan-budget (math.max buffer.chunk-bytes (* columns 4)))
  (var done false)
  (while (and (not done) (< pos buffer.size) (< scanned-bytes scan-budget))
    (local remaining-budget (- scan-budget scanned-bytes))
    (local read-bytes (math.min buffer.chunk-bytes remaining-budget))
    (local chunk (read-composed-range buffer pos read-bytes))
    (if (= (# chunk) 0)
        (set done true)
        (do
          (var i 1)
          (while (and (<= i (# chunk)) (not done))
            (local b (string.byte chunk i))
            (if (= b 10)
                (do
                  (set line-end-byte (+ pos i -1))
                  (set line-end-known? true)
                  (set newline-bytes 1)
                  (set done true))
                (if (= b 13)
                    (do
                      (local next-b (if (< i (# chunk))
                                        (string.byte chunk (+ i 1))
                                        (byte-at buffer (+ pos i))))
                      (set line-end-byte (+ pos i -1))
                      (set line-end-known? true)
                      (set newline-bytes (if (= next-b 10) 2 1))
                      (set done true))
                    (when (< visible-bytes (* columns 4))
                      (table.insert visible-parts (string.char b))
                      (set visible-bytes (+ visible-bytes 1)))))
            (set i (+ i 1)))
          (when (not done)
            (set pos (+ pos (# chunk)))
            (set scanned-bytes (+ scanned-bytes (# chunk)))
            (set line-end-byte pos)))))
  (when (and (not line-end-known?) (< pos buffer.size))
    (set partial? true))
  (when (and (not line-end-known?) (>= pos buffer.size))
    (set line-end-known? true)
    (set line-end-byte buffer.size))
  (local visible-text (table.concat visible-parts ""))
  (local (text cps offsets) (clipped-row-values visible-text columns))
  (set end-byte (+ start-byte (# text)))
  {:line line
   :start-byte start-byte
   :end-byte end-byte
   :line-end-byte line-end-byte
   :line-end-known? line-end-known?
   :partial? partial?
   :newline-bytes newline-bytes
   :text text
   :codepoints cps
   :column-byte-offsets offsets})

(fn delete-range [buffer start-byte end-byte]
  (local start (clamp start-byte 0 buffer.size))
  (local finish (clamp end-byte start buffer.size))
  (when (> finish start)
    (local (before _middle) (split-pieces-at buffer.pieces start))
    (local (_drop after) (split-pieces-at buffer.pieces finish))
    (set buffer.pieces (normalize-pieces (do
                                           (each [_ piece (ipairs after)]
                                             (table.insert before piece))
                                           before)))
    (set buffer.size (total-bytes buffer.pieces))
    (set buffer.cursor-byte start)
    (set buffer.dirty? true)
    (set buffer.line-anchors [{:line 0 :byte 0}])
    true))

(fn clip-row-column [row start-column requested-columns]
  (local full-text row.text)
  (local full-cps row.codepoints)
  (local full-offsets row.column-byte-offsets)
  (local byte-start (if (= (. full-offsets (+ start-column 1)) nil)
                        (# full-text)
                        (. full-offsets (+ start-column 1))))
  (local byte-end (if (= (. full-offsets (+ start-column requested-columns 1)) nil)
                      (# full-text)
                      (. full-offsets (+ start-column requested-columns 1))))
  (set row.text (string.sub full-text (+ byte-start 1) byte-end))
  (set row.codepoints [])
  (local clipped-offsets [0])
  (for [i (+ start-column 1) (math.min (# full-cps) (+ start-column requested-columns))]
    (table.insert row.codepoints (. full-cps i))
    (table.insert clipped-offsets (- (. full-offsets (+ i 1)) byte-start)))
  (set row.start-byte (+ row.start-byte byte-start))
  (set row.end-byte (+ row.start-byte (- byte-end byte-start)))
  (set row.column-byte-offsets clipped-offsets))

(fn get-viewport [buffer view]
  (local start-line (if (= view.line nil) buffer.scroll-line view.line))
  (local start-column (if (= view.column nil) 0 view.column))
  (local requested-lines (if (= view.lines nil) 1 view.lines))
  (local requested-columns (if (= view.columns nil) 80 view.columns))
  (local rows [])
  (var line start-line)
  (var start-byte (find-line-start buffer start-line))
  (for [_ 1 requested-lines]
    (local row (build-row buffer line start-byte (+ start-column requested-columns)))
    (local next-start-byte (if row.line-end-known?
                              (+ row.line-end-byte row.newline-bytes)
                              buffer.size))
    (when (> start-column 0)
      (clip-row-column row start-column requested-columns))
    (table.insert rows row)
    (set start-byte next-start-byte)
    (set line (+ line 1)))
  {:start-line start-line
   :start-column start-column
   :requested-lines requested-lines
   :requested-columns requested-columns
   :rows rows})

(fn insert-text [buffer text]
  (when (not (valid-utf8? text))
    (error "LazyTextBuffer insert-text requires valid UTF-8"))
  (local insert-offset (# buffer.add-buffer))
  (set buffer.add-buffer (.. buffer.add-buffer text))
  (local (before after) (split-pieces-at buffer.pieces buffer.cursor-byte))
  (table.insert before (make-piece :add insert-offset (# text)))
  (each [_ piece (ipairs after)]
    (table.insert before piece))
  (set buffer.pieces (normalize-pieces before))
  (set buffer.size (total-bytes buffer.pieces))
  (set buffer.cursor-byte (+ buffer.cursor-byte (# text)))
  (set buffer.selection nil)
  (set buffer.dirty? true)
  (set buffer.line-anchors [{:line 0 :byte 0}])
  true)

(fn delete-before-cursor [buffer]
  (if (<= buffer.cursor-byte 0)
      false
      (if (delete-range buffer (- buffer.cursor-byte 1) buffer.cursor-byte) true false)))

(fn delete-at-cursor [buffer]
  (if (>= buffer.cursor-byte buffer.size)
      false
      (if (delete-range buffer buffer.cursor-byte (+ buffer.cursor-byte 1)) true false)))

(fn move-caret-to-byte [buffer byte]
  (set buffer.cursor-byte (clamp byte 0 buffer.size))
  true)

(fn move-caret-to-line-column [buffer line column]
  (local start (find-line-start buffer line))
  (local row (build-row buffer line start column))
  (local offsets row.column-byte-offsets)
  (local byte-offset (if (= (. offsets (+ column 1)) nil)
                         (# row.text)
                         (. offsets (+ column 1))))
  (set buffer.cursor-byte (+ start byte-offset))
  true)

(fn scroll-lines [buffer delta]
  (set buffer.scroll-line (math.max 0 (+ buffer.scroll-line delta)))
  true)

(fn set-selection [buffer anchor-byte active-byte]
  (local anchor (clamp anchor-byte 0 buffer.size))
  (local active (clamp active-byte 0 buffer.size))
  (set buffer.selection {:anchor-byte anchor
                         :active-byte active
                         :start-byte (math.min anchor active)
                         :end-byte (math.max anchor active)})
  true)

(fn clear-selection [buffer]
  (set buffer.selection nil)
  true)

(fn get-selected-text [buffer]
  (if buffer.selection
      (read-composed-range buffer buffer.selection.start-byte (- buffer.selection.end-byte buffer.selection.start-byte))
      ""))

(fn build-save-segments [buffer]
  (local segments [])
  (each [_ piece (ipairs buffer.pieces)]
    (if (= piece.source :add)
        (table.insert segments {:text (piece-text piece buffer)})
        (table.insert segments {:source-path buffer.source.path
                                :offset piece.offset
                                :bytes piece.bytes})))
  segments)

(fn collapse-after-save [buffer result]
  (if result.token
      (do
        (set buffer.source.baseline-token result.token)
        (set buffer.source.size result.token.size))
      (buffer.source:refresh-token))
  (set buffer.pieces [(make-piece :original 0 buffer.source.size)])
  (set buffer.add-buffer "")
  (set buffer.size buffer.source.size)
  (set buffer.dirty? false)
  (set buffer.line-anchors [{:line 0 :byte 0}])
  result)

(fn save [buffer _opts]
  (local segments (build-save-segments buffer))
  (local (ok result) (pcall fs.atomic-replace-if-current
                            buffer.source.path
                            segments
                            buffer.source.baseline-token))
  (if ok
      (collapse-after-save buffer result)
      (do
        (set buffer.dirty? true)
        (error result))))

(fn LazyTextBuffer [opts]
  (local source (assert opts.source "LazyTextBuffer requires source"))
  (local chunk-bytes (if (not= opts.chunk-bytes nil)
                         opts.chunk-bytes
                         (if (not= source.chunk-bytes nil)
                             source.chunk-bytes
                             65536)))
  {:source source
   :chunk-bytes chunk-bytes
   :pieces [(make-piece :original 0 source.size)]
   :add-buffer ""
   :size source.size
   :cursor-byte 0
   :scroll-line 0
   :selection nil
   :dirty? false
   :line-anchors [{:line 0 :byte 0}]
   :get-viewport get-viewport
   :insert-text insert-text
   :delete-before-cursor delete-before-cursor
   :delete-at-cursor delete-at-cursor
   :move-caret-to-byte move-caret-to-byte
   :move-caret-to-line-column move-caret-to-line-column
   :scroll-lines scroll-lines
   :set-selection set-selection
   :clear-selection clear-selection
   :get-selected-text get-selected-text
   :save save})

LazyTextBuffer

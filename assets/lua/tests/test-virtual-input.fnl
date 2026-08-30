(local _ (require :main))
(local glm (require :glm))
(local gl (require :gl))
(local BuildContext (require :build-context))
(local VirtualInput (require :virtual-input))
(local fs (require :fs))
(local LazyTextSource (require :lazy-text-source))
(local LazyTextBuffer (require :lazy-text-buffer))
(local InputState (require :input-state-router))
(local States (require :states))
(local StateSystemBindings (require :state-system-bindings))

(local tests [])
(local temp-root "/tmp/space/tests/virtual-input")

(fn codepoints-from-text [text]
  (assert (= (type text) :string) "codepoints-from-text requires text")
  (icollect [_ cp (utf8.codes (or text ""))] cp))

(fn text-from-codepoints [codepoints]
  (assert (= (type codepoints) :table) "text-from-codepoints requires codepoints")
  (table.concat
    (icollect [_ cp (ipairs (or codepoints []))]
              (utf8.char cp))))

(fn row [line text start]
  (assert (= (type line) :number) "row requires line")
  (local start-byte (or start 0))
  (local offsets [0])
  (var last 0)
  (each [byte-index cp (utf8.codes (or text ""))]
    (set last (- (+ byte-index (# (utf8.char cp))) 1))
    (table.insert offsets last))
  {:line line
   :start-byte start-byte
   :end-byte (+ start-byte (# (or text "")))
   :line-end-byte (+ start-byte (# (or text "")))
   :line-end-known? true
   :newline-bytes 1
   :text (or text "")
   :codepoints (codepoints-from-text text)
   :column-byte-offsets offsets})

(fn make-buffer [opts]
  (assert true "make-buffer uses explicit test defaults")
  (local options (or opts {}))
  (local state {:viewport-calls []
                :inserted []
                :deleted-before 0
                :deleted-at 0
                :moved []
                :scrolled []
                :selections []
                :cleared-selection 0
                :deleted-selection 0
                :saved 0})
  (local rows (or options.rows [(row 0 "alpha" 0) (row 1 "beta" 6) (row 2 "gamma" 11)]))
  (local buffer {:cursor-byte (or options.cursor-byte 0)
                 :scroll-line (or options.scroll-line 0)
                 :selection options.selection
                 :dirty? false
                 :state state})
  (set buffer.get-viewport
       (fn [self view]
         (table.insert state.viewport-calls view)
         (local out [])
         (for [i 1 view.lines]
           (local source-row (. rows (+ view.line i)))
           (table.insert out (or source-row (row (+ view.line i -1) ""))))
         {:start-line view.line
          :start-column view.column
          :requested-lines view.lines
          :requested-columns view.columns
          :rows out}))
  (set buffer.insert-text
       (fn [self text]
         (table.insert state.inserted text)
         (set self.cursor-byte (+ self.cursor-byte (# text)))
         (set self.selection nil)
         (set self.dirty? true)
         true))
  (set buffer.delete-before-cursor
       (fn [self]
         (set state.deleted-before (+ state.deleted-before 1))
         (set self.cursor-byte (math.max 0 (- self.cursor-byte 1)))
         true))
  (set buffer.delete-at-cursor
       (fn [_self]
         (set state.deleted-at (+ state.deleted-at 1))
         true))
  (set buffer.move-caret-to-byte
       (fn [self byte]
         (table.insert state.moved byte)
         (set self.cursor-byte byte)
         true))
  (set buffer.move-caret-to-line-column
       (fn [self line column]
         (table.insert state.moved {:line line :column column})
         (set self.cursor-byte (+ (* line 10) column))
         true))
  (set buffer.move-caret-horizontal
       (fn [self delta]
         (table.insert state.moved {:horizontal delta})
         (set self.cursor-byte (math.max 0 (+ self.cursor-byte delta)))
         true))
  (set buffer.scroll-lines
       (fn [self delta]
         (table.insert state.scrolled delta)
         (set self.scroll-line (math.max 0 (+ self.scroll-line delta)))
         true))
  (set buffer.set-selection
       (fn [self anchor active]
         (table.insert state.selections {:anchor anchor :active active})
         (set self.selection {:anchor-byte anchor
                              :active-byte active
                              :start-byte (math.min anchor active)
                              :end-byte (math.max anchor active)})
         true))
  (set buffer.clear-selection
       (fn [self]
         (set state.cleared-selection (+ state.cleared-selection 1))
         (set self.selection nil)
         true))
  (set buffer.delete-selection
       (fn [self]
         (set state.deleted-selection (+ state.deleted-selection 1))
         (set self.selection nil)
         true))
  (set buffer.get-selected-text
       (fn [_self]
         (or options.selected-text "selected")))
  (set buffer.save
       (fn [_self]
         (set state.saved (+ state.saved 1))
         (if options.save-error
             (error options.save-error)
             {:saved true})))
  buffer)

(fn make-clickables-stub []
  (local state {:register 0 :unregister 0})
  (local stub {:state state})
  (set stub.register (fn [_self _obj] (set state.register (+ state.register 1))))
  (set stub.unregister (fn [_self _obj] (set state.unregister (+ state.unregister 1))))
  stub)

(fn make-hoverables-stub []
  (local state {:register 0 :unregister 0})
  (local stub {:state state})
  (set stub.register (fn [_self _obj] (set state.register (+ state.register 1))))
  (set stub.unregister (fn [_self _obj] (set state.unregister (+ state.unregister 1))))
  stub)

(fn make-ctx []
  (BuildContext {:clickables (make-clickables-stub)
                 :hoverables (make-hoverables-stub)}))

(fn make-temp-file [name content]
  (local dir (fs.join-path temp-root (.. name "-" (os.time))))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local path (fs.join-path dir "file.txt"))
  (fs.write-file path content)
  path)

(fn lazy-buffer [name content]
  (local path (make-temp-file name content))
  (LazyTextBuffer {:source (LazyTextSource.file path {:chunk-bytes 4})
                   :chunk-bytes 4}))

(fn snapshot-text [buffer]
  (. (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 80}) :rows 1 :text))

(fn set-test-states []
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :text {})
  (states:set-state :normal)
  (StateSystemBindings.bind-states-host states)
  states)

(fn install-clipboard-spy []
  (local original-set gl.clipboard-set)
  (var copied nil)
  (set gl.clipboard-set (fn [value] (set copied value)))
  {:read (fn [] copied)
   :restore (fn [] (set gl.clipboard-set original-set))})

(fn build-input [opts]
  ((VirtualInput opts) (make-ctx)))

(fn expect-build-without-context []
  ((VirtualInput {:buffer (make-buffer)}) nil))

(fn exercise-copy [input clipboard]
  (assert (= (input:copy-selection) "copy me"))
  (assert (= (clipboard.read) "copy me"))
  (assert (input:on-key-down {:key (string.byte "c") :mod 64})))

(fn save-conflict [input]
  (input:save))

(fn drop-again [input]
  (input:drop))

(fn record-save [input result]
  (assert input.save-results "record-save requires input.save-results")
  (table.insert input.save-results result))

(fn virtual-input-requires-explicit-build-context []
  (local (ok err) (pcall expect-build-without-context))
  (assert (not ok) "VirtualInput should reject missing build context")
  (assert (string.find (tostring err) "VirtualInput requires ctx" 1 true)))

(fn virtual-input-renders-only-visible-viewport-rows []
  (local buffer (make-buffer))
  (local input (build-input {:buffer buffer :line-count 2 :column-count 4}))
  (input:refresh-viewport)
  (assert (= (length input.rows) 2) "should build exactly visible row widgets")
  (assert (= (. buffer.state.viewport-calls 1 :lines) 2))
  (assert (= (. buffer.state.viewport-calls 1 :columns) 4))
  (local first-row (. input.rows 1))
  (local second-row (. input.rows 2))
  (assert (= (text-from-codepoints (first-row:get-codepoints)) "alph"))
  (assert (= (text-from-codepoints (second-row:get-codepoints)) "beta"))
  (input:drop))

(fn virtual-input-caret-navigation-loads-lazy-rows []
  (local buffer (make-buffer))
  (local input (build-input {:buffer buffer :line-count 2 :column-count 6}))
  (input:on-key-down {:key 1073741905})
  (input:on-key-down {:key 1073741903})
  (input:on-key-down {:key 1073741902})
  (assert (= (length buffer.state.moved) 2) "arrow keys should move through the lazy buffer")
  (assert (= (. buffer.state.scrolled 1) 2) "page down should scroll by visible lines")
  (assert (>= (length buffer.state.viewport-calls) 3) "navigation should refresh visible viewport")
  (local handled (input:on-key-down {:key 999999}))
  (assert (= handled false) "unsupported key payloads return false")
  (input:drop))

(fn virtual-input-inserts-and-deletes-through-lazy-buffer []
  (local buffer (make-buffer {:cursor-byte 2 :selection {:anchor-byte 1 :active-byte 3 :start-byte 1 :end-byte 3}}))
  (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
  (input:on-text-input {:text "Z"})
  (input:on-key-down {:key 8})
  (input:on-key-down {:key 127})
  (assert (= (. buffer.state.inserted 1) "Z"))
  (assert (= buffer.state.deleted-selection 1) "normal insertion replaces existing selection")
  (assert (= buffer.state.deleted-before 1))
  (assert (= buffer.state.deleted-at 1))
  (input:drop))

(fn virtual-input-copies-selected-text []
  (local clipboard (install-clipboard-spy))
  (local buffer (make-buffer {:selected-text "copy me"
                              :selection {:anchor-byte 0 :active-byte 4 :start-byte 0 :end-byte 4}}))
  (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
  (local (ok err) (pcall exercise-copy input clipboard))
  (input:drop)
  (clipboard.restore)
  (when (not ok)
    (error err)))

(fn virtual-input-save-reports-success-and-conflict []
  (local successes [])
  (local buffer (make-buffer))
  (local input (build-input {:buffer buffer
                             :line-count 1
                             :column-count 8
                             :on-save record-save}))
  (set input.save-results successes)
  (local ok-result (input:save))
  (assert ok-result.saved)
  (assert (= (length successes) 1))
  (local conflict (build-input {:buffer (make-buffer {:save-error "file changed since token"})
                                :line-count 1
                                :column-count 8}))
  (local (ok err) (pcall save-conflict conflict))
  (assert (not ok) "save conflicts should fail loudly")
  (assert (string.find (tostring err) "file changed since token" 1 true))
  (input:drop)
  (conflict:drop))

(fn virtual-input-drop-tears-down-owned-children []
  (local ctx (make-ctx))
  (local input ((VirtualInput {:buffer (make-buffer) :line-count 3 :column-count 8}) ctx))
  (input:drop)
  (assert (= ctx.clickables.state.unregister 1) "drop should unregister direct pointer child")
  (local (ok err) (pcall drop-again input))
  (assert (not ok) "double drop should error")
  (assert (string.find (tostring err) "VirtualInput dropped twice" 1 true)))

(fn virtual-input-click-focus-routes-input-state-events []
  (local states (set-test-states))
  (local buffer (make-buffer))
  (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
  (input:on-click {:row-index 1 :column 0})
  (assert (= (InputState.active-input) input) "click should make VirtualInput active input")
  (assert (= (states:active-name) :text) "click should enter text input state")
  (assert (InputState.dispatch-input :on-text-input {:text "R"}) "routed text input should be handled")
  (assert (= (. buffer.state.inserted 1) "R"))
  (input:drop)
  (assert (not (InputState.active-input)) "drop should release active VirtualInput"))

(fn virtual-input-insertion-replaces-real-buffer-selection []
  (local buffer (lazy-buffer "selection-replace" "abcde"))
  (buffer:move-caret-to-byte 1)
  (buffer:set-selection 1 3)
  (local input (build-input {:buffer buffer :line-count 1 :column-count 10}))
  (input:insert-text "Z")
  (assert (= (snapshot-text buffer) "aZde") "selection bytes should be replaced by inserted text")
  (input:drop))

(fn virtual-input-caret-navigation-scrolls-to-target-row []
  (local rows [(row 0 "zero" 0) (row 1 "one" 10) (row 2 "two" 20) (row 3 "three" 30)])
  (local buffer (make-buffer {:rows rows :cursor-byte 10}))
  (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
  (input:refresh-viewport)
  (input:on-key-down {:key 1073741905})
  (local last-view (. buffer.state.viewport-calls (length buffer.state.viewport-calls)))
  (assert (= last-view.line 1) "moving to row beyond viewport should scroll requested rows")
  (input:drop))

(fn virtual-input-horizontal-navigation-preserves-utf8-boundaries []
  (local buffer (lazy-buffer "utf8-nav" "éx"))
  (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
  (input:on-key-down {:key 1073741903})
  (assert (= buffer.cursor-byte 2) "right arrow should advance over the whole UTF-8 character")
  (input:on-key-down {:key 1073741904})
  (assert (= buffer.cursor-byte 0) "left arrow should return to previous UTF-8 boundary")
  (input:drop))

(fn virtual-input-horizontal-crossing-newline-scrolls-viewport []
  (local buffer (lazy-buffer "horizontal-newline-scroll" "aa\nbb\ncc"))
  (buffer:move-caret-to-byte 5)
  (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
  (input:refresh-viewport)
  (input:on-key-down {:key 1073741903})
  (assert (= buffer.cursor-byte 6) "right arrow should cross the newline to next row start")
  (assert (= input.scroll-line 1) "crossing below the viewport should scroll target row into view")
  (input:drop))

(fn move-without-safe-horizontal [input]
  (input:on-key-down {:key 1073741903}))

(fn virtual-input-horizontal-navigation-requires-safe-buffer-api []
  (local buffer (make-buffer {:rows [(row 0 "éx" 0)]}))
  (set buffer.move-caret-horizontal nil)
  (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
  (local (ok err) (pcall move-without-safe-horizontal input))
  (assert (not ok) "horizontal movement without safe buffer API should fail loudly")
  (assert (string.find (tostring err) "move-caret-horizontal" 1 true))
  (assert (= buffer.cursor-byte 0) "unsafe fallback must not move by raw bytes")
  (input:drop))

(fn virtual-input-layout-hides-off-viewport-caret []
  (local rows [(row 0 "zero" 0) (row 1 "one" 10) (row 2 "two" 20)])
  (local buffer (make-buffer {:rows rows :cursor-byte 30 :scroll-line 0}))
  (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
  (input.layout:measurer)
  (set input.layout.size input.layout.measure)
  (input.layout:layouter)
  (assert (= input.caret.visible? false) "off-viewport cursor should not render caret on first visible row")
  (input:drop))

(table.insert tests {:name "VirtualInput requires explicit build context" :fn virtual-input-requires-explicit-build-context})
(table.insert tests {:name "VirtualInput renders only visible viewport rows" :fn virtual-input-renders-only-visible-viewport-rows})
(table.insert tests {:name "VirtualInput caret navigation loads lazy rows" :fn virtual-input-caret-navigation-loads-lazy-rows})
(table.insert tests {:name "VirtualInput inserts and deletes through lazy buffer" :fn virtual-input-inserts-and-deletes-through-lazy-buffer})
(table.insert tests {:name "VirtualInput copies selected text" :fn virtual-input-copies-selected-text})
(table.insert tests {:name "VirtualInput save reports success and conflict" :fn virtual-input-save-reports-success-and-conflict})
(table.insert tests {:name "VirtualInput drop tears down owned children" :fn virtual-input-drop-tears-down-owned-children})
(table.insert tests {:name "VirtualInput click focus routes InputState events" :fn virtual-input-click-focus-routes-input-state-events})
(table.insert tests {:name "VirtualInput insertion replaces real buffer selection" :fn virtual-input-insertion-replaces-real-buffer-selection})
(table.insert tests {:name "VirtualInput caret navigation scrolls to target row" :fn virtual-input-caret-navigation-scrolls-to-target-row})
(table.insert tests {:name "VirtualInput horizontal navigation preserves UTF-8 boundaries" :fn virtual-input-horizontal-navigation-preserves-utf8-boundaries})
(table.insert tests {:name "VirtualInput horizontal crossing newline scrolls viewport" :fn virtual-input-horizontal-crossing-newline-scrolls-viewport})
(table.insert tests {:name "VirtualInput horizontal navigation requires safe buffer API" :fn virtual-input-horizontal-navigation-requires-safe-buffer-api})
(table.insert tests {:name "VirtualInput layout hides off-viewport caret" :fn virtual-input-layout-hides-off-viewport-caret})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "virtual-input"
                       :tests tests})))

{:name "virtual-input"
 :tests tests
 :main main}

(local _ (require :main))
(local InputModel (require :input-model))

(local tests [])

(fn input-model-text-ops []
  (local model (InputModel {:text "abc"}))
  (assert (= (model:get-text) "abc"))
  (assert (= model.cursor-index 3))
  (model:move-caret-to 1)
  (model:insert-text "Z")
  (assert (= (model:get-text) "aZbc"))
  (assert (= model.cursor-index 2))
  (model:delete-before-cursor)
  (assert (= (model:get-text) "abc"))
  (assert (= model.cursor-index 1))
  (model:delete-at-cursor)
  (assert (= (model:get-text) "ac"))
  (assert (= model.cursor-index 1))
  (model:move-caret -1)
  (assert (= model.cursor-index 0))
  (model:drop))

(fn input-model-signals []
  (var change-count 0)
  (var last-text nil)
  (local model (InputModel {:text ""}))
  (model.changed:connect
    (fn [text]
      (set change-count (+ change-count 1))
      (set last-text text)))
  (model:set-text "A")
  (assert (= change-count 1))
  (model:insert-text "B")
  (assert (= change-count 2))
  (model:move-caret 1)
  (assert (= change-count 2))
  (assert (= last-text "AB"))
  (model:drop))

(fn input-model-mode-transitions []
  (local modes [])
  (local model (InputModel {}))
  (model.mode-changed:connect
    (fn [mode]
      (table.insert modes mode)))
  (assert (= model.mode :normal))
  (assert (not (model:on-text-input {:text "x"})))
  (model:enter-insert-mode)
  (assert (= (. modes 1) :insert))
  (assert (model:on-text-input {:text "x"}))
  (assert (= model.mode :insert))
  (model:on-state-disconnected {})
  (assert (= model.mode :normal))
  (assert (= (. modes 2) :normal))
  (assert (not model.connected?))
  (model:on-state-connected {})
  (assert model.connected?)
  (model:drop))

(fn input-model-scrolls-column-when-caret-jumps []
  (local model (InputModel {:text "abcdefghijkl"}))
  (model:set-viewport-columns 5)
  (model:move-caret-to 0)
  (assert (= model.scroll-column 0))
  (local last-column (math.max 0 (- (length model.codepoints) 1)))
  (model:move-caret-to last-column)
  (assert (= model.cursor-column last-column))
  (local expected (- model.cursor-column (- model.viewport-columns 1)))
  (assert (= model.scroll-column expected))
  (model:drop))

(table.insert tests {:name "Input model edits text and cursors" :fn input-model-text-ops})
(table.insert tests {:name "Input model emits change events" :fn input-model-signals})
(table.insert tests {:name "Input model handles modes and state" :fn input-model-mode-transitions})
(table.insert tests {:name "Input model scrolls columns when caret jumps" :fn input-model-scrolls-column-when-caret-jumps})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "input-model"
                       :tests tests})))

{:name "input-model"
 :tests tests
 :main main}

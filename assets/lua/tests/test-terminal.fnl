(local tests [])

(local terminal (require :terminal))
(fn terminal-basic-shape []
  (local term (terminal.Terminal 4 8))
  (term:clear-dirty-regions)
  (local size (term:get-size))
  (assert (= size.rows 4))
  (assert (= size.cols 8))
  (assert (= (term:get-title) nil))
  (local cell (term:get-cell 0 0))
  (assert (= cell.codepoint 32)))

(fn terminal-resize-emits-dirty []
  (local term (terminal.Terminal 2 2))
  (term:clear-dirty-regions)
  (var fired false)
  (set term.on-screen-updated (fn [] (set fired true)))
  (term:resize 3 5)
  (local size (term:get-size))
  (assert (= size.rows 3))
  (assert (= size.cols 5))
  (local dirty (term:get-dirty-regions))
  (assert (> (# dirty) 0))
  (assert fired))

(fn terminal-update-yields-on-flooded-output []
  (local term (terminal.Terminal 2 2))
  (if (not (term:is-pty-available))
      (print "Skipping flooded-output update test: PTY unavailable")
      (do
        (var screen-updated? false)
        (set term.on-screen-updated (fn [] (set screen-updated? true)))

        (term:send-text "yes\n")
        (local start (os.clock))
        ; Ensure update returns quickly even while the child is still flooding output.
        (for [i 1 3]
          (term:update))
        (local elapsed (* (- (os.clock) start) 1000))
        (local deadline (+ (os.clock) 1.0))
        (while (and (not screen-updated?) (< (os.clock) deadline))
          (term:update))
        (term:send-text (string.char 3)) ; Ctrl-C to stop the writer.
        (term:update)

        (assert screen-updated?)
        (when (term:is-scrollback-supported)
          (assert (> (term:get-scrollback-size) 0)))
        (assert (< elapsed 200)))))

(table.insert tests {:name "terminal reports size and blank cell" :fn terminal-basic-shape})
(table.insert tests {:name "terminal resize marks dirty regions" :fn terminal-resize-emits-dirty})
(table.insert tests {:name "terminal update yields when output floods PTY" :fn terminal-update-yields-on-flooded-output})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "terminal"
                       :tests tests})))

{:name "terminal"
 :tests tests
 :main main}

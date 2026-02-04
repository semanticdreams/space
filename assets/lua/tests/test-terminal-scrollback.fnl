(local tests [])

(local terminal (require :terminal))
(fn cells->text [cells]
  (local chars [])
  (each [_ cell (ipairs cells)]
    (table.insert chars (string.char cell.codepoint)))
  (string.match (table.concat chars) "^%s*(.-)%s*$"))

(fn scrollback-captures-lines []
  (local term (terminal.Terminal 2 4))
  (when (not (term:is-scrollback-supported))
    (print "Skipping scrollback capture test: scrollback unsupported")
    (return))
  (term:set-scrollback-limit 3)
  (term:inject-output "aa\n")
  (term:inject-output "bb\n")
  (term:inject-output "cc\ndd\n")
  (local final-size (term:get-scrollback-size))
  (assert (= final-size 3))
  (assert (= (cells->text (term:get-scrollback-line 0)) "bb"))
  (assert (= (cells->text (term:get-scrollback-line 1)) ""))
  (assert (= (cells->text (term:get-scrollback-line 2)) "cc")))

(fn alt-screen-suppresses-scrollback []
  (local term (terminal.Terminal 2 3))
  (when (not (term:is-scrollback-supported))
    (print "Skipping alt-screen scrollback test: scrollback unsupported")
    (return))
  (term:set-scrollback-limit 4)
  (term:inject-output "alpha\nbeta\n")
  (local before (term:get-scrollback-size))
  (term:inject-output "\27[?1049h")
  (assert (term:is-alt-screen))
  (term:inject-output "gamma\ndelta\n")
  (assert (= before (term:get-scrollback-size)))
  (term:inject-output "\27[?1049l")
  (assert (not (term:is-alt-screen))))

(table.insert tests {:name "terminal collects scrollback lines" :fn scrollback-captures-lines})
(table.insert tests {:name "terminal alt-screen disables scrollback accumulation" :fn alt-screen-suppresses-scrollback})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "terminal-scrollback"
                       :tests tests})))

{:name "terminal-scrollback"
 :tests tests
 :main main}

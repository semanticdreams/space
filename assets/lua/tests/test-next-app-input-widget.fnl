(local _ (require :main))
(local InputWidget (require :next-app/input-widget))
(local NextLayout (require :next-app/layout))
(local {: FocusManager} (require :focus))

(local tests [])

(fn make-focus-context []
  (local manager (FocusManager {:root-name "next-input-test"}))
  (local root (manager:get-root-scope))
  (local scope (manager:create-scope {:name "next-input-scope"}))
  (manager:attach scope root)
  (local ctx {})
  (set ctx.create-node
       (fn [_self opts]
         (local node (manager:create-node opts))
         (manager:attach node scope)
         node))
  (set ctx.attach-bounds
       (fn [_self node opts]
         (when (and node opts opts.get-focus-bounds)
           (set node.get-focus-bounds opts.get-focus-bounds))))
  {:focus ctx :manager manager})

(fn next-input-insert-backspace-and-cursor []
  (local input (InputWidget {:text "abc"}))
  (input:move-cursor -1)
  (input:insert-text "Z")
  (assert (= (input:get-text) "abZc"))
  (input:backspace)
  (assert (= (input:get-text) "abc")))

(fn next-input-focus-toggle-controls-caret-and-placeholder []
  (local input (InputWidget {:text ""}))
  (NextLayout.run-frame input 1.0 0.2 0)
  (assert (input.placeholder-node:visible?))
  (assert (not (input.caret:visible?)))
  (input:set-focused true)
  (NextLayout.run-frame input 1.0 0.2 0)
  (assert (input.caret:visible?))
  (input:insert-text "hello")
  (NextLayout.run-frame input 1.0 0.2 0)
  (assert (not (input.placeholder-node:visible?))))

(fn next-input-focus-manager-integration []
  (local focus-data (make-focus-context))
  (local input (InputWidget {:text "focus"
                             :focus focus-data.focus}))
  (assert input.focus-node)
  (input:on-click {:button 1})
  (assert (= (focus-data.manager:get-focused-node) input.focus-node))
  (assert input.focused?)
  (focus-data.manager:clear-focus)
  (assert (not input.focused?))
  (input:drop)
  (focus-data.manager:drop))

(table.insert tests {:name "Next input supports insert/backspace/cursor movement"
                     :fn next-input-insert-backspace-and-cursor})
(table.insert tests {:name "Next input focus toggles caret and placeholder"
                     :fn next-input-focus-toggle-controls-caret-and-placeholder})
(table.insert tests {:name "Next input integrates with focus manager"
                     :fn next-input-focus-manager-integration})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-app-input-widget"
                       :tests tests})))

{:name "next-app-input-widget"
 :tests tests
 :main main}

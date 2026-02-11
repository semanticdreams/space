(local BuildContext (require :build-context))
(local FennelInterpreterView (require :fennel-interpreter-view))

(local tests [])

(fn make-clickables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  (set stub.register-right-click (fn [_self _obj] nil))
  (set stub.unregister-right-click (fn [_self _obj] nil))
  (set stub.register-double-click (fn [_self _obj] nil))
  (set stub.unregister-double-click (fn [_self _obj] nil))
  (set stub.register-left-click-void-callback (fn [_self _cb] nil))
  (set stub.unregister-left-click-void-callback (fn [_self _cb] nil))
  (set stub.register-right-click-void-callback (fn [_self _cb] nil))
  (set stub.unregister-right-click-void-callback (fn [_self _cb] nil))
  stub)

(fn make-hoverables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  stub)

(fn make-icons-stub []
  (local glyph {:advance 1
                :planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}
               :advance 1})
  (local stub {:font font})
  (set stub.resolve
       (fn [_self _name]
         {:type :font
          :codepoint 4242
          :font font}))
  stub)

(fn with-view [f opts]
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local icons (make-icons-stub))
  (local ctx (BuildContext {:clickables clickables
                            :hoverables hoverables
                            :icons icons
                            :pointer-target {}}))
  (local view ((FennelInterpreterView (or opts {})) ctx))
  (local (ok err) (pcall f view))
  (view:drop)
  (if (not ok)
      (error err)))

(fn interpreter-runs-source-on-ctrl-enter []
  (with-view
    (fn [view]
      (view.input:set-text "(+ 1 2)")
      (local handled (view.input:on-key-down {:key 13 :mod 64}))
      (assert handled "Ctrl+Enter should be handled")
      (assert (= (length view.entries) 2))
      (assert (= (. (. view.entries 1) :content) "(+ 1 2)"))
      (assert (= (. (. view.entries 2) :content) "3")))))

(fn interpreter-records-errors []
  (with-view
    (fn [view]
      (view.input:set-text "(error \"boom\")")
      (local handled (view:run))
      (assert handled "run should execute non-empty source")
      (assert (= (length view.entries) 2))
      (assert (= (. (. view.entries 2) :prefix) "! "))
      (assert (string.find (. (. view.entries 2) :content) "boom" 1 true)))))

(fn interpreter-clear-output-removes-entries []
  (with-view
    (fn [view]
      (view.input:set-text "(+ 1 2)")
      (view:run)
      (assert (> (length view.entries) 0))
      (view:clear-output)
      (assert (= (length view.entries) 0)))))

(fn interpreter-wraps-output-lines []
  (with-view
    (fn [view]
      (local line
        (view:format-entry-line
          {:prefix "< "
           :content "alpha beta gamma delta"}))
      (assert (string.find line "\n" 1 true)
              "Expected wrapped output line to include newline"))
    {:output-wrap-columns 10}))

(table.insert tests {:name "FennelInterpreterView runs source on Ctrl+Enter"
                     :fn interpreter-runs-source-on-ctrl-enter})
(table.insert tests {:name "FennelInterpreterView records eval errors"
                     :fn interpreter-records-errors})
(table.insert tests {:name "FennelInterpreterView clear output removes entries"
                     :fn interpreter-clear-output-removes-entries})
(table.insert tests {:name "FennelInterpreterView wraps output lines"
                     :fn interpreter-wraps-output-lines})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "fennel-interpreter-view"
                       :tests tests})))

{:name "fennel-interpreter-view"
 :tests tests
 :main main}

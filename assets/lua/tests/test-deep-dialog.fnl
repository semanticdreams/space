(local tests [])
(local glm (require :glm))
(local BuildContext (require :build-context))
(local DeepDialog (require :deep-dialog))
(local Text (require :text))

(local icons-stub {:resolve (fn [_self _name] nil)})

(fn deep-dialog-builds-and-computes-depth []
  (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                            :hoverables (assert app.hoverables "test requires app.hoverables")
                            :icons icons-stub
                            :theme (app.themes.get-active-theme)}))
  (local builder
    (DeepDialog {:title "Deep"
                 :depth 2
                 :child (Text {:text "Content"})}))
  (local dialog (builder ctx))
  (assert dialog "DeepDialog build missing entity")
  (assert dialog.layout "DeepDialog missing layout")
  (assert dialog.drop "DeepDialog missing drop")
  (dialog.layout:measurer)
  (local measure (or dialog.layout.measure (glm.vec3 0 0 0)))
  (assert (= measure.z 2) "DeepDialog :depth should override measured depth")
  (dialog:drop))

(table.insert tests {:name "DeepDialog builds and computes depth" :fn deep-dialog-builds-and-computes-depth})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "deep-dialog"
                       :tests tests})))

{:name "deep-dialog"
 :tests tests
 :main main}

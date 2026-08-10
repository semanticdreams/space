(local tests [])
(local glm (require :glm))
(local BuildContext (require :build-context))
(local DeepDialog (require :deep-dialog))
(local LightTheme (require :light-theme))
(local MathUtils (require :math-utils))
(local Text (require :text))

(local approx (. MathUtils :approx))

(fn color= [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)
       (approx a.w b.w)))

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

(fn deep-dialog-default-light-titlebar-and-sides-use-tertiary []
  (local theme (LightTheme))
  (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                            :hoverables (assert app.hoverables "test requires app.hoverables")
                            :icons icons-stub
                            :theme theme}))
  (local dialog ((DeepDialog {:title "Deep"
                              :depth 2
                              :child (Text {:text "Content"})}) ctx))
  (local tertiary-background theme.button.variants.tertiary.background)
  (assert tertiary-background "LightTheme must expose tertiary background for DeepDialog surfaces")
  (assert (color= dialog.titlebar.background-color tertiary-background)
          "Default light DeepDialog titlebar should use tertiary")
  (local side-face (. dialog.cuboid.faces 2))
  (assert (color= side-face.color tertiary-background)
          "Default light DeepDialog sides should use tertiary")
  (assert (not (color= dialog.titlebar.background-color theme.button.variants.secondary.background))
          "Default light DeepDialog titlebar should not fall back to secondary")
  (dialog:drop))

(table.insert tests {:name "DeepDialog builds and computes depth" :fn deep-dialog-builds-and-computes-depth})
(table.insert tests {:name "DeepDialog default light titlebar and sides use tertiary"
                     :fn deep-dialog-default-light-titlebar-and-sides-use-tertiary})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "deep-dialog"
                       :tests tests})))

{:name "deep-dialog"
 :tests tests
 :main main}

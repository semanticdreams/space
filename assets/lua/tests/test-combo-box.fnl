(local glm (require :glm))
(local _ (require :main))
(local ComboBox (require :combo-box))
(local Button (require :button))
(local BuildContext (require :build-context))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local {: FocusManager} (require :focus))
(local MathUtils (require :math-utils))

(local tests [])

(local approx (. MathUtils :approx))

(fn make-icons-stub []
    (local glyph {:advance 1})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {65533 glyph
                             4242 glyph}})
    (local stub {:font font
                 :codepoints {:arrow_drop_down 4242}})
    (set stub.get
         (fn [self name]
             (local value (. self.codepoints name))
             (assert value (.. "Missing icon " name))
             value))
    (set stub.resolve
         (fn [self name]
             (local code (self:get name))
             {:type :font
              :codepoint code
              :font self.font}))
    stub)

(fn make-ctx []
    (local icons-stub (make-icons-stub))
    (set app.themes {:get-active-theme (fn [] {:font icons-stub.font
                                                 :text {:scale 1.0}})})
    (local intersector (Intersectables))
    (local clickables (Clickables {:intersectables intersector}))
    (local hoverables (Hoverables {:intersectables intersector}))
    (BuildContext {:clickables clickables
                   :hoverables hoverables
                   :icons icons-stub}))

(fn make-focus-ctx []
    (local intersector (Intersectables))
    (local clickables (Clickables {:intersectables intersector}))
    (local hoverables (Hoverables {:intersectables intersector}))
    (local manager (FocusManager {:root-name "combo-box-test"}))
    (local root (manager:get-root-scope))
    (local scope (manager:create-scope {:name "combo-box-scope"}))
    (manager:attach scope root)
    {:ctx (BuildContext {:focus-manager manager
                         :focus-scope scope
                         :clickables clickables
                         :hoverables hoverables
                         :icons (make-icons-stub)})
     :manager manager})

(fn combo-box-selects-and-emits []
    (local ctx (make-ctx))
    (local combo
        ((ComboBox {:items ["user" "assistant" "system"]
                    :value "assistant"})
         ctx))
    (assert (= (combo:get-value) "assistant"))
    (assert (= (combo:get-label) "assistant"))
    (var emitted nil)
    (local handler (combo.changed:connect (fn [value]
                                              (set emitted value))))
    (combo:set-value "user")
    (assert (= (combo:get-value) "user"))
    (assert (= (combo:get-label) "user"))
    (assert (= emitted "user"))
    (combo.changed:disconnect handler true)
    (combo:drop))

(fn combo-box-toggle-updates-layout []
    (local ctx (make-ctx))
    (local combo
        ((ComboBox {:items ["a" "b" "c" "d"]
                    :value "a"
                    :max-menu-height 6})
         ctx))
    (combo.layout:measurer)
    (local closed-height combo.layout.measure.y)
    (combo:open)
    (combo.layout:measurer)
    (local open-height combo.layout.measure.y)
    (assert (approx open-height closed-height)
            "ComboBox open state should not affect layout height")
    (combo:close)
    (combo.layout:measurer)
    (local reopened-height combo.layout.measure.y)
    (assert (approx reopened-height closed-height)
            "ComboBox close state should restore layout height")
    (combo:drop))

(fn combo-box-clears-removed-selection []
    (local ctx (make-ctx))
    (local combo
        ((ComboBox {:items ["left" "right"]
                    :value "left"
                    :placeholder "Pick one"})
         ctx))
    (assert (= (combo:get-value) "left"))
    (combo:set-items ["right"])
    (assert (= (combo:get-value) nil))
    (assert (= (combo:get-label) "Pick one"))
    (combo:drop))

(fn combo-box-closes-after-layout []
    (local ctx (make-ctx))
    (local combo
        ((ComboBox {:items ["alpha" "beta"]
                    :value "alpha"})
         ctx))
    (combo:open)
    (combo.layout:measurer)
    (set combo.layout.size combo.layout.measure)
    (set combo.layout.position (glm.vec3 0 0 0))
    (set combo.layout.rotation (glm.quat 1 0 0 0))
    (set combo.layout.depth-offset-index 0)
    (combo.layout:layouter)
    (local open-clip (and combo.list-view
                          combo.list-view.scroll-view
                          combo.list-view.scroll-view.scroll
                          combo.list-view.scroll-view.scroll.layout
                          combo.list-view.scroll-view.scroll.layout.clip-region))
    (assert open-clip "ComboBox list should have a clip region when open")
    (local open-size (or (and open-clip.bounds open-clip.bounds.size) (glm.vec3 0 0 0)))
    (assert (> open-size.y 0) "ComboBox list clip should be non-zero when open")
    (combo:close)
    (combo.layout:measurer)
    (set combo.layout.size combo.layout.measure)
    (combo.layout:layouter)
    (local closed-clip (and combo.list-view
                            combo.list-view.scroll-view
                            combo.list-view.scroll-view.scroll
                            combo.list-view.scroll-view.scroll.layout
                            combo.list-view.scroll-view.scroll.layout.clip-region))
    (assert closed-clip "ComboBox list should keep a clip region when closed")
    (local closed-size (or (and closed-clip.bounds closed-clip.bounds.size) (glm.vec3 0 0 0)))
    (assert (approx closed-size.y 0) "ComboBox list clip should collapse when closed")
    (combo:drop))

(fn combo-box-closes-on-focus-loss []
    (local setup (make-focus-ctx))
    (local ctx setup.ctx)
    (local combo
        ((ComboBox {:items ["system" "user" "assistant"]
                    :value "assistant"})
         ctx))
    (local other ((Button {:text "Other"}) ctx))
    (combo:open)
    (assert combo.open?)
    (other:request-focus)
    (assert (not combo.open?) "ComboBox should close when focus leaves")
    (combo:drop)
    (other:drop))

(fn combo-box-closed-skips-list-focus []
    (local setup (make-focus-ctx))
    (local ctx setup.ctx)
    (local manager setup.manager)
    (local combo
        ((ComboBox {:items ["system" "user" "assistant"]
                    :value "assistant"})
         ctx))
    (local other ((Button {:text "Other"}) ctx))
    (combo.button:request-focus)
    (manager:focus-next {})
    (assert (= (manager:get-focused-node) other.focus-node)
            "ComboBox list items should not receive focus when closed")
    (combo:drop)
    (other:drop))

(table.insert tests {:name "ComboBox selects and emits" :fn combo-box-selects-and-emits})
(table.insert tests {:name "ComboBox open/close updates layout" :fn combo-box-toggle-updates-layout})
(table.insert tests {:name "ComboBox clears selection when items change" :fn combo-box-clears-removed-selection})
(table.insert tests {:name "ComboBox closes after layout" :fn combo-box-closes-after-layout})
(table.insert tests {:name "ComboBox closes on focus loss" :fn combo-box-closes-on-focus-loss})
(table.insert tests {:name "ComboBox closed skips list focus"
                     :fn combo-box-closed-skips-list-focus})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "combo-box"
                       :tests tests})))

{:name "combo-box"
 :tests tests
 :main main}

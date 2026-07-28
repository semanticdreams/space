(local glm (require :glm))
(local _ (require :main))
(local ButtonWidget (require :next-app/button-widget))
(local NextLayout (require :next-app/layout))
(local NextLayoutFlex (require :next-app/flex))
(local TextWidget (require :next-app/text-widget))
(local {: FocusManager} (require :focus))

(local tests [])

(local MathUtils (require :math-utils))
(local approx (. MathUtils :approx))
(fn color= [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)
       (approx a.w b.w)))

(fn make-clickables-stub []
  (local state {:register 0
                :unregister 0
                :register-right 0
                :unregister-right 0
                :register-double 0
                :unregister-double 0})
  (local stub {:state state})
  (set stub.register (fn [_self _obj] (set state.register (+ state.register 1))))
  (set stub.unregister (fn [_self _obj] (set state.unregister (+ state.unregister 1))))
  (set stub.register-right-click (fn [_self _obj] (set state.register-right (+ state.register-right 1))))
  (set stub.unregister-right-click (fn [_self _obj] (set state.unregister-right (+ state.unregister-right 1))))
  (set stub.register-double-click (fn [_self _obj] (set state.register-double (+ state.register-double 1))))
  (set stub.unregister-double-click (fn [_self _obj] (set state.unregister-double (+ state.unregister-double 1))))
  stub)

(fn make-hoverables-stub []
  (local state {:register 0 :unregister 0})
  (local stub {:state state})
  (set stub.register (fn [_self _obj] (set state.register (+ state.register 1))))
  (set stub.unregister (fn [_self _obj] (set state.unregister (+ state.unregister 1))))
  stub)


(fn stub-clickables []
  {:register (fn [_ _] nil)
   :unregister (fn [_ _] nil)
   :register-right-click (fn [_ _] nil)
   :unregister-right-click (fn [_ _] nil)
   :register-double-click (fn [_ _] nil)
   :unregister-double-click (fn [_ _] nil)})

(fn stub-hoverables []
  {:register (fn [_ _] nil)
   :unregister (fn [_ _] nil)})

(fn make-system-cursors-stub []
  (local state {:calls [] :last nil})
  (local stub {:state state})
  (set stub.set-cursor
       (fn [_self name]
         (set state.last name)
         (table.insert state.calls name)))
  stub)

(fn make-icons-stub []
  (local glyph {:advance 1
                :planeBounds {:left 0 :right 1 :bottom 0 :top 1}
                :atlasBounds {:left 0 :right 1 :bottom 0 :top 1}})
  (local font {:metadata {:metrics {:ascender 1 :descender -1 :lineHeight 1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}})
  (local stub {:font font :codepoints {:star 4242}})
  (set stub.get (fn [self name] (. self.codepoints name)))
  (set stub.resolve (fn [self name]
                      {:type :font
                       :codepoint (self:get name)
                       :font self.font}))
  stub)

(fn make-probe-node [w h]
  (NextLayout.Node.new
    {:name "probe"
     :measure-fn (fn [self _mw _mh _md]
                   (self:set-measure w h 0))
     :layout-fn (fn [self width height depth]
                  (self:set-size width height depth {:mark-dirty? false}))}))

(fn make-focus-context []
  (local manager (FocusManager {:root-name "next-button-test"}))
  (local root (manager:get-root-scope))
  (local scope (manager:create-scope {:name "next-button-scope"}))
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

(fn run-frame [node]
  (NextLayout.run-frame node 1.4 0.5 0))

(fn next-button-registers-with-clickables []
  (local clickables (make-clickables-stub))
  (local button (ButtonWidget {:text "A"
                               :clickables clickables
                               :hoverables (make-hoverables-stub)}))
  (assert (= clickables.state.register 1))
  (assert (= clickables.state.register-right 1))
  (assert (= clickables.state.register-double 1))
  (button:drop)
  (assert (= clickables.state.unregister 1))
  (assert (= clickables.state.unregister-right 1))
  (assert (= clickables.state.unregister-double 1)))

(fn next-button-registers-with-hoverables []
  (local hoverables (make-hoverables-stub))
  (local button (ButtonWidget {:text "A"
                               :hoverables hoverables
                               :clickables (make-clickables-stub)}))
  (assert (= hoverables.state.register 1))
  (button:drop)
  (assert (= hoverables.state.unregister 1)))

(fn next-button-click-invokes-callback-and-signal []
  (var callback-count 0)
  (var signal-count 0)
  (local button
    (ButtonWidget {:text "Emit"
                   :clickables (make-clickables-stub)
                   :hoverables (make-hoverables-stub)
                   :on-click (fn [_self _event]
                               (set callback-count (+ callback-count 1)))}))
  (button.clicked.connect (fn [_event]
                            (set signal-count (+ signal-count 1))))
  (button:on-click {:button 1})
  (assert (= callback-count 1))
  (assert (= signal-count 1)))

(fn next-button-right-and-double-click-callbacks []
  (var right-callbacks 0)
  (var double-callbacks 0)
  (local button
    (ButtonWidget {:text "Callbacks"
                   :on-right-click (fn [_self _event]
                                     (set right-callbacks (+ right-callbacks 1)))
                   :on-double-click (fn [_self _event]
                                      (set double-callbacks (+ double-callbacks 1))) :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (button:on-right-click {:button 2})
  (button:on-double-click {:button 1})
  (assert (= right-callbacks 1))
  (assert (= double-callbacks 1)))

(fn next-button-right-and-double-click-signals []
  (var right-count 0)
  (var double-count 0)
  (local button (ButtonWidget {:text "Clicks" :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (button.right-clicked.connect (fn [_event]
                                  (set right-count (+ right-count 1))))
  (button.double-clicked.connect (fn [_event]
                                   (set double-count (+ double-count 1))))
  (button:on-right-click {:button 2})
  (button:on-double-click {:button 1})
  (assert (= right-count 1))
  (assert (= double-count 1)))

(fn next-button-intersect-misses-outside-bounds []
  (local button (ButtonWidget {:text "Miss" :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (button:set-frame 0.2 0.3 0 0.6 0.2 0 (glm.quat 1 0 0 0) {:mark-dirty? false})
  (button:run-layout 0.6 0.2 0)
  (NextLayout.run-frame button 0.6 0.2 0)
  (local ray {:origin (glm.vec3 2.0 2.0 -1)
              :direction (glm.vec3 0 0 1)})
  (let [(hit point distance) (button:intersect ray)]
    (assert (= hit false))
    (assert (= point nil))
    (assert (= distance nil))))

(fn next-button-hover-updates-color []
  (local base (glm.vec4 0.3 0.3 0.3 1))
  (local hover (glm.vec4 0.6 0.5 0.4 1))
  (local button (ButtonWidget {:text "Hover"
                               :background-color base
                               :hover-background-color hover :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (button:on-hovered true)
  (assert (color= button.rectangle.color hover))
  (button:on-hovered false)
  (assert (color= button.rectangle.color base)))

(fn next-button-defaults-to-theme-colors []
  (local button (ButtonWidget {:text "Theme" :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (assert (color= button.background-color button.rectangle.color))
  (assert button.hover-background-color)
  (assert button.pressed-background-color))

(fn next-button-hover-updates-cursor []
  (local cursors (make-system-cursors-stub))
  (local button (ButtonWidget {:text "Cursor"
                               :system-cursors cursors :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (button:on-hovered true)
  (assert (= cursors.state.last "hand"))
  (button:on-hovered false)
  (assert (= cursors.state.last "arrow")))

(fn next-button-icon-uses-icons-font []
  (local icons (make-icons-stub))
  (local button (ButtonWidget {:icon :star
                               :icons icons :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (local codepoints (button.text:get-text))
  (assert (= button.icon :star))
  (assert codepoints))

(fn next-button-custom-child-used-directly []
  (local child (make-probe-node 0.2 0.1))
  (local button (ButtonWidget {:child child :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (assert (= button.child child)))

(fn next-button-centers-content-when-taller []
  (local button (ButtonWidget {:text "Center" :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (run-frame button)
  (button:set-size 1.0 0.4 0)
  (NextLayout.run-frame button 1.0 0.4 0)
  (assert (>= button.child.local-y 0)))

(fn next-button-pressed-color []
  (local pressed (glm.vec4 0.8 0.1 0.1 1))
  (local button (ButtonWidget {:text "Press"
                               :pressed-background-color pressed :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (button:on-pressed true)
  (assert (color= button.rectangle.color pressed))
  (button:on-pressed false)
  (assert (color= button.rectangle.color button.background-color)))

(fn next-button-ghost-visibility []
  (local button (ButtonWidget {:text "Ghost"
                               :variant :ghost :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (assert (not (button.rectangle:visible?)))
  (button:on-hovered true)
  (assert (button.rectangle:visible?))
  (button:on-hovered false)
  (assert (not (button.rectangle:visible?))))

(fn next-button-solid-keeps-visibility []
  (local button (ButtonWidget {:text "Solid" :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (assert (button.rectangle:visible?))
  (button:on-hovered false)
  (assert (button.rectangle:visible?)))

(fn next-button-focus-overlay []
  (local button (ButtonWidget {:text "Focus" :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (assert button.focus-overlay)
  (assert (not (button.focus-overlay:visible?)))
  (button:on-click {:button 1})
  (assert button.focused?)
  (assert (button.focus-overlay:visible?)))

(fn next-button-focus-manager-integration []
  (local focus-data (make-focus-context))
  (local button (ButtonWidget {:text "Focus manager"
                               :focus focus-data.focus :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (assert button.focus-node)
  (assert (not button.focused?))
  (button:on-click {:button 1})
  (assert (= (focus-data.manager:get-focused-node) button.focus-node))
  (assert button.focused?)
  (assert (button.focus-overlay:visible?))
  (button:set-enabled false)
  (assert (= (focus-data.manager:get-focused-node) nil))
  (assert (= button.focused? false))
  (button:drop)
  (focus-data.manager:drop))

(fn next-button-renders-icon-and-label-and-trailing []
  (local icons (make-icons-stub))
  (local trailing (TextWidget {:text "T" :scale 0.05}))
  (local button (ButtonWidget {:icon :star
                               :icons icons
                               :text "Launch"
                               :trailing trailing :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (assert (= button.child.name "next-button-content"))
  (assert (= (length button.child.children) 3)))

(fn next-button-set-enabled-disables-handlers []
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local button (ButtonWidget {:text "Enable"
                               :clickables clickables
                               :hoverables hoverables}))
  (button:set-enabled false)
  (assert (= button.enabled? false))
  (assert (color= button.background-color (glm.vec4 0.25 0.25 0.25 0.5)))
  (button:set-enabled true)
  (assert (= button.enabled? true)))

(fn next-button-set-text-updates-label []
  (local button (ButtonWidget {:text "Before" :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (button:set-text "After")
  (assert (= (button.label:get-text) "After")))

(fn next-button-set-color-updates-rectangle []
  (local color (glm.vec4 0.7 0.2 0.1 1))
  (local button (ButtonWidget {:text "Tint" :clickables (stub-clickables) :hoverables (stub-hoverables)}))
  (button:set-color color)
  (assert (color= button.background-color color))
  (assert (color= button.rectangle.color color)))

(table.insert tests {:name "Next button registers/unregisters with clickables"
                     :fn next-button-registers-with-clickables})
(table.insert tests {:name "Next button registers/unregisters with hoverables"
                     :fn next-button-registers-with-hoverables})
(table.insert tests {:name "Next button click invokes callback and signal"
                     :fn next-button-click-invokes-callback-and-signal})
(table.insert tests {:name "Next button right/double callbacks invoke options handlers"
                     :fn next-button-right-and-double-click-callbacks})
(table.insert tests {:name "Next button emits right and double click signals"
                     :fn next-button-right-and-double-click-signals})
(table.insert tests {:name "Next button intersect misses outside bounds"
                     :fn next-button-intersect-misses-outside-bounds})
(table.insert tests {:name "Next button background color changes on hover"
                     :fn next-button-hover-updates-color})
(table.insert tests {:name "Next button defaults to resolved theme colors"
                     :fn next-button-defaults-to-theme-colors})
(table.insert tests {:name "Next button hover toggles system cursor"
                     :fn next-button-hover-updates-cursor})
(table.insert tests {:name "Next button uses icon font when icon option provided"
                     :fn next-button-icon-uses-icons-font})
(table.insert tests {:name "Next button uses supplied child without wrapping"
                     :fn next-button-custom-child-used-directly})
(table.insert tests {:name "Next button centers content when taller"
                     :fn next-button-centers-content-when-taller})
(table.insert tests {:name "Next button pressed state uses pressed color"
                     :fn next-button-pressed-color})
(table.insert tests {:name "Next button ghost variant toggles rectangle visibility"
                     :fn next-button-ghost-visibility})
(table.insert tests {:name "Next button solid variant keeps rectangle visible"
                     :fn next-button-solid-keeps-visibility})
(table.insert tests {:name "Next button shows focus overlay when focused"
                     :fn next-button-focus-overlay})
(table.insert tests {:name "Next button integrates with focus manager"
                     :fn next-button-focus-manager-integration})
(table.insert tests {:name "Next button renders icon, label, and trailing widget"
                     :fn next-button-renders-icon-and-label-and-trailing})
(table.insert tests {:name "Next button set-enabled toggles interaction state"
                     :fn next-button-set-enabled-disables-handlers})
(table.insert tests {:name "Next button set-text updates label widget"
                     :fn next-button-set-text-updates-label})
(table.insert tests {:name "Next button set-color updates background state"
                     :fn next-button-set-color-updates-rectangle})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-app-button"
                       :tests tests})))

{:name "next-app-button"
 :tests tests
 :main main}

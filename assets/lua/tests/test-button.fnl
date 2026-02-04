(local glm (require :glm))
(local _ (require :main))
(local Button (require :button))
(local Rectangle (require :rectangle))
(local BuildContext (require :build-context))
(local {: FocusManager} (require :focus))
(local {: Layout} (require :layout))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))

(local tests [])

(local colors (require :colors))
(local MathUtils (require :math-utils))
(local approx (. MathUtils :approx))

(fn color= [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)
       (approx a.w b.w)))

(fn make-vector-buffer []
  (local state {:allocate 0
                :delete 0})
  (local buffer {:state state})
  (set buffer.allocate (fn [_self _count]
                         (set state.allocate (+ state.allocate 1))
                         state.allocate))
  (set buffer.delete (fn [_self _handle]
                       (set state.delete (+ state.delete 1))))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  buffer)

(fn make-test-ctx [opts]
  (local AppBootstrap (require :app-bootstrap))
  (AppBootstrap.init-themes)
  (local options (or opts {}))
  (local intersector (or options.intersectables (Intersectables)))
  (local clickables (or options.clickables (Clickables {:intersectables intersector})))
  (local hoverables (or options.hoverables (Hoverables {:intersectables intersector})))
  (local triangle (make-vector-buffer))
  (local text-buffer (make-vector-buffer))
  (local ctx {:triangle-vector triangle})
  (set ctx.get-text-vector (fn [_self _font] text-buffer))
  (set ctx.theme options.theme)
  (set ctx.clickables clickables)
  (set ctx.hoverables hoverables)
  (set ctx.system-cursors options.system-cursors)
  (set ctx.icons options.icons)
  ctx)

(fn make-focus-build-ctx [opts]
  (local options (or opts {}))
  (local intersector (or options.intersectables (Intersectables)))
  (local clickables (or options.clickables (Clickables {:intersectables intersector})))
  (local hoverables (or options.hoverables (Hoverables {:intersectables intersector})))
  (local manager (FocusManager {:root-name "button-test"}))
  (local root (manager:get-root-scope))
  (local scope (manager:create-scope {:name "button-scope"}))
  (manager:attach scope root)
  {:ctx (BuildContext {:focus-manager manager
                           :focus-scope scope
                           :clickables clickables
                           :hoverables hoverables
                           :system-cursors options.system-cursors})
   :manager manager})

(fn make-clickables-stub []
  (local state {:register 0
                :unregister 0
                :register-right 0
                :unregister-right 0
                :register-double 0
                :unregister-double 0})
  (local stub {:state state})
  (set stub.register (fn [_self _obj]
                       (set state.register (+ state.register 1))))
  (set stub.unregister (fn [_self _obj]
                         (set state.unregister (+ state.unregister 1))))
  (set stub.register-right-click (fn [_self _obj]
                                   (set state.register-right (+ state.register-right 1))))
  (set stub.unregister-right-click (fn [_self _obj]
                                     (set state.unregister-right (+ state.unregister-right 1))))
  (set stub.register-double-click (fn [_self _obj]
                                    (set state.register-double (+ state.register-double 1))))
  (set stub.unregister-double-click (fn [_self _obj]
                                      (set state.unregister-double (+ state.unregister-double 1))))
  stub)

(fn make-hoverables-stub []
  (local state {:register 0
                :unregister 0})
  (local stub {:state state})
  (set stub.register (fn [_self _obj]
                       (set state.register (+ state.register 1))))
  (set stub.unregister (fn [_self _obj]
                         (set state.unregister (+ state.unregister 1))))
  (set stub.on-enter (fn []))
  (set stub.on-leave (fn []))
  (set stub.on-mouse-motion (fn [_self _payload]))
  stub)

(fn make-system-cursors-stub []
  (local state {:calls []
                :last nil})
  (local stub {:state state})
  (set stub.set-cursor (fn [_self name]
                         (set state.last name)
                         (table.insert state.calls name)))
  (set stub.reset (fn [_self] nil))
  (set stub.drop (fn [_self] nil))
  stub)

(fn with-clickables-stub [body]
  (local stub (make-clickables-stub))
  (let [(ok result) (pcall body stub)]
    (when (not ok)
      (error result))
    result))

(fn with-hoverables-stub [body]
  (local stub (make-hoverables-stub))
  (let [(ok result) (pcall body stub)]
    (when (not ok)
      (error result))
    result))

(fn with-system-cursors-stub [body]
  (local stub (make-system-cursors-stub))
  (let [(ok result) (pcall body stub)]
    (when (not ok)
      (error result))
    result))

(fn make-icons-stub []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}
               :advance 1})
  (local stub {:font font
               :codepoints {:star 4242}})
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

(fn with-icons-stub [body]
  (local stub (make-icons-stub))
  (let [(ok result) (pcall body stub)]
    (when (not ok)
      (error result))
    result))

(fn make-probe-widget [name]
  (fn build [_ctx]
    (local layout
      (Layout {:name (or name "probe")
               :measurer (fn [self]
                           (set self.measure (glm.vec3 0 0 0)))
               :layouter (fn [_self] nil)}))
    (fn drop [self]
      (self.layout:drop))
    {:layout layout :drop drop}))

(fn button-registers-with-clickables []
  (with-clickables-stub
    (fn [stub]
      (local ctx (make-test-ctx {:clickables stub}))
      (local builder (Button {:text "A"}))
      (local button (builder ctx))
      (assert (= stub.state.register 1))
      (assert (= stub.state.register-right 1))
      (assert (= stub.state.register-double 1))
      (button:drop)
      (assert (= stub.state.unregister 1))
      (assert (= stub.state.unregister-right 1))
      (assert (= stub.state.unregister-double 1)))))

(fn button-intersect-forwards-to-layout []
  (with-clickables-stub
    (fn [_stub]
      (local ctx (make-test-ctx {:clickables _stub}))
      (local button ((Button {:text "Hit"}) ctx))
      (set button.layout.size (glm.vec3 1 1 1))
      (set button.layout.position (glm.vec3 0 0 0))
      (set button.layout.rotation (glm.quat 1 0 0 0))
      (local ray {:origin (glm.vec3 0.5 0.5 -1) :direction (glm.vec3 0 0 1)})
      (let [(hit point distance) (button:intersect ray)]
        (assert hit)
        (assert point)
        (assert (> distance 0)))
      (button:drop))))

(fn button-click-callbacks-and-signals []
  (with-clickables-stub
    (fn [_stub]
      (local ctx (make-test-ctx {:clickables _stub}))
      (var callback-count 0)
      (var signal-count 0)
      (local builder
        (Button {:text "Emit"
                 :on-click (fn [_self _event]
                             (set callback-count (+ callback-count 1)))}))
      (local button (builder ctx))
      (local clicked button.clicked)
      (local handler (fn [_event]
                       (set signal-count (+ signal-count 1))))
      (clicked.connect handler)
      (button:on-click {:button 1})
      (assert (= callback-count 1))
      (assert (= signal-count 1))
      (button:drop))))

(fn button-centers-padding-when-taller []
  (with-hoverables-stub
    (fn [hover]
      (with-clickables-stub
        (fn [click]
          (local ctx (make-test-ctx {:clickables click :hoverables hover}))
          (local button ((Button {:text "Center"}) ctx))
          (button.layout:measurer)
          (set button.layout.size (glm.vec3 6 10 1))
          (set button.layout.position (glm.vec3 0 0 0))
          (set button.layout.rotation (glm.quat 1 0 0 0))
          (button.layout:layouter)
          (local padding-size button.padding.layout.size)
          (local expected-offset (/ (- button.layout.size.y padding-size.y) 2))
          (print (.. "DEBUG: Button Y=" button.layout.size.y " PaddingContent Y=" padding-size.y " Expected=" expected-offset " Actual=" button.padding.layout.position.y))
          (assert (approx button.padding.layout.position.y expected-offset))
          (button:drop))))))

(fn button-registers-with-hoverables []
  (with-hoverables-stub
    (fn [stub]
      (local ctx (make-test-ctx {:hoverables stub}))
      (local builder (Button {:text "Hover"}))
      (local button (builder ctx))
      (assert (= stub.state.register 1))
      (button:drop)
      (assert (= stub.state.unregister 1)))))

(fn button-hovered-updates-color []
  (with-hoverables-stub
    (fn [_stub]
      (local ctx (make-test-ctx {:hoverables _stub}))
      (local base (glm.vec4 0.3 0.3 0.3 1))
      (local hover (glm.vec4 0.6 0.5 0.4 1))
      (local button ((Button {:text "Hover"
                              :background-color base
                              :hover-background-color hover}) ctx))
      (button:on-hovered true)
      (assert (color= button.rectangle.color hover))
      (button:on-hovered false)
      (assert (color= button.rectangle.color base))
      (button:drop))))

(fn button-hovered-updates-system-cursor []
  (with-system-cursors-stub
    (fn [stub]
      (local ctx (make-test-ctx {:system-cursors stub}))
      (local button ((Button {:text "Cursor"}) ctx))
      (button:on-hovered true)
      (assert (= stub.state.last "hand"))
      (button:on-hovered false)
      (assert (= stub.state.last "arrow"))
      (button:drop))))

(fn button-icon-option-uses-icons-font []
  (with-icons-stub
    (fn [icons]
      (local ctx (make-test-ctx {:icons icons}))
      (local button ((Button {:icon :star}) ctx))
      (local codepoints (button.text.child:get-codepoints))
      (assert (= (length codepoints) 1))
      (assert (= (. codepoints 1) (icons:get :star)))
      (assert (= button.text.child.style.font icons.font))
      (assert (= button.icon :star))
      (button:drop))))

(fn button-custom-child-is-used-directly []
  (with-hoverables-stub
    (fn [hover]
      (with-clickables-stub
        (fn [click]
          (local ctx (make-test-ctx {:clickables click :hoverables hover}))
          (local color (glm.vec4 0.25 0.5 0.75 1))
          (local child-builder (Rectangle {:color color}))
          (local button ((Button {:child child-builder}) ctx))
          (assert (not button.padding))
          (assert (not button.text))
          (assert (= button.child button.aligned.child))
          (assert (color= button.child.color color))
          (button:drop))))))

(fn button-uses-theme-variant-default []
  (local variant-colors
    {:background (glm.vec4 0.11 0.21 0.31 1)
     :hover-background (glm.vec4 0.2 0.3 0.4 1)
     :pressed-background (glm.vec4 0.05 0.1 0.15 1)
     :foreground (glm.vec4 0.9 0.9 0.95 1)})
  (local theme {:button {:default-variant :secondary
                         :variants {:secondary variant-colors}}})
  (local ctx (make-test-ctx {:theme theme}))
  (local button ((Button {:text "Theme default"}) ctx))
  (assert (color= button.background-color variant-colors.background))
  (assert (color= button.hover-background-color variant-colors.hover-background))
  (assert (color= button.pressed-background-color variant-colors.pressed-background))
  (assert (color= button.foreground-color variant-colors.foreground))
  (button:drop))

(fn button-pressed-state-overrides-color []
  (local ctx (make-test-ctx))
  (local pressed (glm.vec4 0.8 0.1 0.1 1))
  (local button ((Button {:text "Press me"
                          :pressed-background-color pressed}) ctx))
  (button:on-pressed true)
  (assert (color= button.rectangle.color pressed))
  (button:on-pressed false)
  (assert (color= button.rectangle.color button.background-color))
  (button:drop))

(fn button-ghost-variant-hides-rectangle []
  (with-hoverables-stub
    (fn [hover]
      (with-clickables-stub
        (fn [click]
          (local ctx (make-test-ctx {:clickables click :hoverables hover}))
          (local button ((Button {:text "Ghost"
                                  :variant :ghost}) ctx))
          (assert (not button.rectangle.visible?))
          (button:on-hovered true)
          (assert button.rectangle.visible?)
          (button:on-hovered false)
          (assert (not button.rectangle.visible?))
          (button:on-pressed true)
          (assert button.rectangle.visible?)
          (button:on-pressed false)
          (assert (not button.rectangle.visible?))
          (button:drop))))))

(fn button-solid-variant-keeps-rectangle-visible []
  (with-hoverables-stub
    (fn [hover]
      (with-clickables-stub
        (fn [click]
          (local ctx (make-test-ctx {:clickables click :hoverables hover}))
          (local button ((Button {:text "Solid"}) ctx))
          (assert button.rectangle.visible?)
          (button:on-hovered false)
          (assert button.rectangle.visible?)
          (button:on-pressed true)
          (assert button.rectangle.visible?)
          (button:on-pressed false)
          (assert button.rectangle.visible?)
          (button:drop))))))

(fn button-focus-overlay-shows-when-focused []
  (with-clickables-stub
    (fn [stub]
      (local focus (make-focus-build-ctx {:clickables stub}))
      (local ctx focus.ctx)
      (local button ((Button {:text "Focus"}) ctx))
      (local overlay button.focus-overlay)
      (assert overlay "Button should create focus overlay when focus context exists")
      (assert (not overlay.visible?) "Focus overlay hidden before focus")
      (button:on-click {:button 1})
      (assert button.focused? "Button becomes focused after click")
      (assert overlay.visible? "Focus overlay visible while focused")
      (assert (= (focus.manager:get-focused-node) button.focus-node)
              "Focus manager should reflect button focus")
      (button:drop)
      (focus.manager:drop))))

(fn button-rectangle-set-visible-reuses-buffer []
  (with-hoverables-stub
    (fn [hover]
      (with-clickables-stub
        (fn [click]
          (local ctx (make-test-ctx {:clickables click :hoverables hover}))
          (local button ((Button {:text "Rect"}) ctx))
          (local state ctx.triangle-vector.state)
          (assert (= state.allocate 1))
          (assert (= state.delete 0))
          (button.rectangle:set-visible false)
          (assert (= state.delete 1))
          (button.rectangle:set-visible true)
          (assert (= state.allocate 2))
          (button:drop)
          (assert (= state.delete 2)))))))

(fn button-renders-icon-and-label []
  (with-icons-stub
    (fn [icons]
      (local ctx (make-test-ctx {:icons icons}))
      (local button ((Button {:icon "star"
                              :text "Launch"}) ctx))
      (local padding button.padding)
      (assert padding "Button should wrap content in padding")
      (local content padding.child)
      (assert content "Button padding should include content")
      (assert (= content.layout.name "flex")
              "Button should use a flex row for icon and label")
      (assert (= (length content.children) 2)
              "Button should render icon and label when both provided")
      (button:drop))))

(fn button-supports-trailing-widget []
  (with-icons-stub
    (fn [icons]
      (local ctx (make-test-ctx {:icons icons}))
      (local trailing (make-probe-widget "trailing-probe"))
      (local button ((Button {:icon "star"
                              :text "Next"
                              :trailing trailing}) ctx))
      (local padding button.padding)
      (local content (and padding padding.child))
      (assert content "Button padding should include content")
      (assert (= (length content.children) 3)
              "Button should render icon, label, and trailing widget")
      (local last-meta (. content.children 3))
      (local last-element (and last-meta last-meta.element))
      (assert last-element "Trailing widget should be present")
      (assert (= last-element.layout.name "trailing-probe")
              "Trailing widget should render after the label")
      (button:drop))))

(table.insert tests {:name "Button registers/unregisters with clickables" :fn button-registers-with-clickables})
(table.insert tests {:name "Button intersect forwards to layout" :fn button-intersect-forwards-to-layout})
(table.insert tests {:name "Button click invokes callback and signal" :fn button-click-callbacks-and-signals})
(table.insert tests {:name "Button registers/unregisters with hoverables" :fn button-registers-with-hoverables})
(table.insert tests {:name "Button background color changes on hover" :fn button-hovered-updates-color})
(table.insert tests {:name "Button hover toggles system cursor" :fn button-hovered-updates-system-cursor})
(table.insert tests {:name "Button uses icon font when icon option provided" :fn button-icon-option-uses-icons-font})
(table.insert tests {:name "Button uses supplied child without padding" :fn button-custom-child-is-used-directly})
(table.insert tests {:name "Button centers padding when taller than content" :fn button-centers-padding-when-taller})
(table.insert tests {:name "Button defaults to theme variant colors" :fn button-uses-theme-variant-default})
(table.insert tests {:name "Button pressed state uses pressed color" :fn button-pressed-state-overrides-color})
(table.insert tests {:name "Button ghost variant only shows rectangle when interactive" :fn button-ghost-variant-hides-rectangle})
(table.insert tests {:name "Button solid variants keep rectangle visible" :fn button-solid-variant-keeps-rectangle-visible})
(table.insert tests {:name "Button shows focus overlay when focused" :fn button-focus-overlay-shows-when-focused})
(table.insert tests {:name "Button rectangle visibility toggles buffer handles" :fn button-rectangle-set-visible-reuses-buffer})
(table.insert tests {:name "Button renders icon and label" :fn button-renders-icon-and-label})
(table.insert tests {:name "Button supports trailing widget" :fn button-supports-trailing-widget})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "button"
                       :tests tests})))

{:name "button"
 :tests tests
 :main main}

(local glm (require :glm))
(local _ (require :main))
(local Card (require :card))
(local Text (require :text))
(local TextStyle (require :text-style))
(local MathUtils (require :math-utils))
(local {: resolve-qr-colors : resolve-chrome-background} (require :widget-theme-utils))

(local tests [])

(local approx (. MathUtils :approx))

(fn color= [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)
       (approx a.w b.w)))

(fn make-vector-buffer []
  (local buffer {})
  (set buffer.allocate (fn [_self _count] 1))
  (set buffer.delete (fn [_self _handle] nil))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  buffer)

(fn make-text-ssbo-batcher []
  {:upsert-text (fn [_self _key _opts] nil)
   :update-text-transform (fn [_self _key _opts] nil)
   :remove-text (fn [_self _key] nil)})

(fn make-test-ctx [opts]
  (local options (or opts {}))
  (local triangle (make-vector-buffer))
  (local text-buffer (make-vector-buffer))
  (local text-ssbo-batcher (make-text-ssbo-batcher))
  (local ctx {:triangle-vector triangle})
  (set ctx.get-text-vector (fn [_self _font] text-buffer))
  (set ctx.get-text-ssbo-batcher (fn [_self] text-ssbo-batcher))
  (set ctx.theme options.theme)
  ctx)

(fn card-defaults-to-theme-colors []
  (local theme
    {:card {:background (glm.vec4 0.2 0.2 0.3 1)
            :foreground (glm.vec4 0.9 0.9 0.95 1)}})
  (local ctx (make-test-ctx {:theme theme}))
  (local card ((Card {:child (Text {:text "child"})}) ctx))
  (assert (color= card.background-color theme.card.background))
  (assert (color= card.foreground-color theme.card.foreground))
  (card:drop))

(fn text-defaults-to-theme-color []
  (local theme {:text {:foreground (glm.vec4 0.8 0.85 0.9 1)}})
  (local ctx (make-test-ctx {:theme theme}))
  (local span ((Text {:text "hello"}) ctx))
  (assert (color= span.style.color theme.text.foreground))
  (span:drop))

(fn text-style-picks-theme-font-variants []
  (local previous app.themes)
  (local theme {:font {:name :regular}
                :italic-font {:name :italic}
                :bold-font {:name :bold}
                :bold-italic-font {:name :bold-italic}})
  (set app.themes {:get-active-theme (fn [] theme)})
  (local style (TextStyle {:bold? true :italic? true}))
  (assert (= style.font theme.bold-italic-font))
  (assert (= style.bold-font theme.bold-font))
  (assert (= style.italic-font theme.italic-font))
  (assert (= style.bold-italic-font theme.bold-italic-font))
  (set app.themes previous))

(fn qr-colors-default-to-theme []
  (local theme {:qr-code {:foreground (glm.vec4 0.1 0.2 0.3 1)
                          :background (glm.vec4 0.95 0.96 0.97 1)}})
  (local ctx (make-test-ctx {:theme theme}))
  (local colors (resolve-qr-colors ctx {}))
  (assert (color= colors.foreground theme.qr-code.foreground))
  (assert (color= colors.background theme.qr-code.background)))

(fn chrome-background-resolves-theme-tokens []
  (local rail (glm.vec4 0.11 0.12 0.13 1))
  (local panel (glm.vec4 0.21 0.22 0.23 1))
  (local theme {:chrome {:rail-background rail
                         :panel-background panel}
                :card {:background (glm.vec4 0.31 0.32 0.33 1)}})
  (local ctx (make-test-ctx {:theme theme}))
  (assert (color= (resolve-chrome-background ctx :rail) rail)
          "Rail background should use theme.chrome.rail-background")
  (assert (color= (resolve-chrome-background ctx :panel) panel)
          "Panel background should use theme.chrome.panel-background"))

(fn chrome-background-falls-back-without-black []
  (local card-bg (glm.vec4 0.4 0.41 0.42 1))
  (local ctx (make-test-ctx {:theme {:card {:background card-bg}}}))
  (local panel (resolve-chrome-background ctx :panel))
  (local rail (resolve-chrome-background nil :rail))
  (assert (color= panel card-bg)
          "Panel fallback should use theme.card.background when present")
  (assert (not (color= rail (glm.vec4 0 0 0 1)))
          "Missing theme rail fallback should not be black"))

(fn text-supports-scale-without-style []
  (local theme {:text {:foreground (glm.vec4 0.3 0.35 0.4 1)}})
  (local ctx (make-test-ctx {:theme theme}))
  (local span ((Text {:text "hello" :scale 0.5}) ctx))
  (assert (color= span.style.color theme.text.foreground)
          "text scale should resolve foreground from ctx.theme")
  (assert (approx span.style.scale 0.5)
          "text scale should use provided scale value")
  (span:drop))

(fn text-style-prefers-provided-theme []
  (local previous app.themes)
  (local global-theme {:font {:name :global}
                       :text {:foreground (glm.vec4 0.9 0.2 0.2 1)
                              :scale 2.0}})
  (set app.themes {:get-active-theme (fn [] global-theme)})
  (local local-theme {:font {:name :local}
                      :text {:foreground (glm.vec4 0.2 0.65 0.2 1)
                             :scale 1.2}})
  (local style (TextStyle {:theme local-theme}))
  (assert (color= style.color local-theme.text.foreground)
          "TextStyle should use local theme foreground")
  (assert (approx style.scale local-theme.text.scale)
          "TextStyle should use local theme scale")
  (assert (= style.font local-theme.font)
          "TextStyle should use local theme font")
  (set app.themes previous))

(fn text-style-falls-back-on-partial-theme []
  (local previous app.themes)
  (local global-theme {:font {:name :global}
                       :text {:foreground (glm.vec4 0.9 0.2 0.2 1)
                              :scale 2.0}})
  (set app.themes {:get-active-theme (fn [] global-theme)})
  (local partial-theme {:text {:foreground (glm.vec4 0.2 0.65 0.2 1)}})
  (local style (TextStyle {:theme partial-theme}))
  (assert (color= style.color partial-theme.text.foreground)
          "should use local text foreground")
  (assert (approx style.scale global-theme.text.scale)
          "should fall back to global scale when local theme has none")
  (assert style.font
          "should fall back to global font when local theme has none")
  (set app.themes previous))

(fn text-defaults-scale-from-ctx-theme []
  (local theme {:text {:foreground (glm.vec4 0.3 0.35 0.4 1)
                       :scale 3.0}})
  (local ctx (make-test-ctx {:theme theme}))
  (local span ((Text {:text "hello"}) ctx))
  (assert (color= span.style.color theme.text.foreground)
          "should resolve foreground from ctx.theme")
  (assert (approx span.style.scale 3.0)
          "should resolve default scale from ctx.theme.text.scale")
  (span:drop))

(table.insert tests {:name "Card pulls colors from theme" :fn card-defaults-to-theme-colors})
(table.insert tests {:name "Text defaults to theme foreground color" :fn text-defaults-to-theme-color})
(table.insert tests {:name "Text supports :scale without explicit TextStyle" :fn text-supports-scale-without-style})
(table.insert tests {:name "Text defaults scale from ctx.theme" :fn text-defaults-scale-from-ctx-theme})
(table.insert tests {:name "TextStyle resolves bold/italic fonts from theme" :fn text-style-picks-theme-font-variants})
(table.insert tests {:name "TextStyle prefers provided :theme over global" :fn text-style-prefers-provided-theme})
(table.insert tests {:name "TextStyle falls back on partial theme" :fn text-style-falls-back-on-partial-theme})
(table.insert tests {:name "QR colors default to theme values" :fn qr-colors-default-to-theme})
(table.insert tests {:name "Chrome background resolves theme tokens"
                     :fn chrome-background-resolves-theme-tokens})
(table.insert tests {:name "Chrome background falls back without black"
                     :fn chrome-background-falls-back-without-black})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "theme-widgets"
                       :tests tests})))

{:name "theme-widgets"
 :tests tests
 :main main}

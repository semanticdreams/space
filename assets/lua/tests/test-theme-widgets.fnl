(local glm (require :glm))
(local _ (require :main))
(local Card (require :card))
(local Text (require :text))
(local TextStyle (require :text-style))
(local MathUtils (require :math-utils))

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

(fn make-test-ctx [opts]
  (local options (or opts {}))
  (local triangle (make-vector-buffer))
  (local text-buffer (make-vector-buffer))
  (local ctx {:triangle-vector triangle})
  (set ctx.get-text-vector (fn [_self _font] text-buffer))
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

(table.insert tests {:name "Card pulls colors from theme" :fn card-defaults-to-theme-colors})
(table.insert tests {:name "Text defaults to theme foreground color" :fn text-defaults-to-theme-color})
(table.insert tests {:name "TextStyle resolves bold/italic fonts from theme" :fn text-style-picks-theme-font-variants})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "theme-widgets"
                       :tests tests})))

{:name "theme-widgets"
 :tests tests
 :main main}

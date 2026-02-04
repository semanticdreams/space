(local glm (require :glm))
(local _ (require :main))
(local Input (require :input))
(local BuildContext (require :build-context))
(local {: FocusManager} (require :focus))
(local {: LayoutRoot} (require :layout))
(local InputState (require :input-state-router))
(local TextState (require :text-state))
(local InsertState (require :insert-state))
(local {: fallback-glyph} (require :text-utils))
(local gl (require :gl))
(local callbacks (require :callbacks))

(local tests [])

(fn codepoints->text [codepoints]
  (table.concat
    (icollect [_ codepoint (ipairs codepoints)]
              (utf8.char codepoint))))

(local MathUtils (require :math-utils))
(local approx (. MathUtils :approx))

(fn queue-size [queue]
  (var count 0)
  (each [_ _ (pairs queue.lookup)]
    (set count (+ count 1)))
  count)

(fn make-clickables-stub []
  (local state {:register 0 :unregister 0})
  (local stub {:state state})
  (set stub.register (fn [_self _obj]
                       (set state.register (+ state.register 1))))
  (set stub.unregister (fn [_self _obj]
                         (set state.unregister (+ state.unregister 1))))
  (set stub.register-right-click (fn [_self _obj]
                                   (set state.register-right-click (+ (or state.register-right-click 0) 1))))
  (set stub.unregister-right-click (fn [_self _obj]
                                     (set state.unregister-right-click (+ (or state.unregister-right-click 0) 1))))
  (set stub.register-double-click (fn [_self _obj]
                                    (set state.register-double-click (+ (or state.register-double-click 0) 1))))
  (set stub.unregister-double-click (fn [_self _obj]
                                      (set state.unregister-double-click (+ (or state.unregister-double-click 0) 1))))
  stub)

(fn make-hoverables-stub []
  (local state {:register 0 :unregister 0})
  (local stub {:state state})
  (set stub.register (fn [_self _obj]
                       (set state.register (+ state.register 1))))
  (set stub.unregister (fn [_self _obj]
                         (set state.unregister (+ state.unregister 1))))
  stub)

(fn make-system-cursors-stub []
  (local state {:calls []})
  (local stub {:state state})
  (set stub.set-cursor (fn [_self name]
                         (table.insert state.calls name)
                         (set state.last name)))
  stub)

(fn with-pointer-stubs [body]
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local cursors (make-system-cursors-stub))
  (let [(ok result) (pcall body {:clickables clickables
                                 :hoverables hoverables
                                 :cursors cursors})]
    (when (not ok)
      (error result))
    result))

(fn make-focus-build-ctx [opts]
  (local options (or opts {}))
  (local manager (FocusManager {:root-name "input-test"}))
  (local root (manager:get-root-scope))
  (local scope (manager:create-scope {:name "input-scope"}))
  (manager:attach scope root)
  {:ctx (BuildContext {:focus-manager manager
                           :focus-scope scope
                           :clickables options.clickables
                           :hoverables options.hoverables
                           :system-cursors options.cursors})
   :manager manager})

(fn make-first-person-stub []
  (local state {:key-down 0 :key-up 0})
  (local stub {:state state})
  (set stub.on-key-down (fn [_self _payload]
                          (set state.key-down (+ state.key-down 1))))
  (set stub.on-key-up (fn [_self _payload]
                        (set state.key-up (+ state.key-up 1))))
  (set stub.on-mouse-button-down (fn [_self _payload] nil))
  (set stub.on-mouse-button-up (fn [_self _payload] nil))
  (set stub.on-mouse-motion (fn [_self _payload] nil))
  (set stub.on-mouse-wheel (fn [_self _payload] nil))
  (set stub.on-controller-button-down (fn [_self _payload] nil))
  (set stub.on-controller-axis-motion (fn [_self _payload] nil))
  (set stub.on-controller-device-removed (fn [_self _payload] nil))
  (set stub.update (fn [_self _delta] nil))
  stub)

(fn with-first-person-controls [stub body]
  (local original app.first-person-controls)
  (set app.first-person-controls stub)
  (let [(ok result) (pcall body stub)]
    (set app.first-person-controls original)
    (when (not ok)
      (error result))
    result))

(fn make-menu-manager-stub []
  (local state {:opened nil})
  (local stub {:state state})
  (set stub.open (fn [_self opts]
                   (set state.opened opts)))
  (set stub.drop (fn [_self] nil))
  stub)

(fn with-menu-manager [stub body]
  (local original app.menu-manager)
  (set app.menu-manager stub)
  (let [(ok result) (pcall body stub)]
    (set app.menu-manager original)
    (when (not ok)
      (error result))
    result))

(fn with-settings [settings f]
  (local previous app.settings)
  (set app.settings settings)
  (local (ok result) (pcall f))
  (set app.settings previous)
  (if ok
      result
      (error result)))

(local wait-until
  (fn [pred]
    (callbacks.run-loop {:poll-jobs false
                         :poll-http false
                         :poll-process true
                         :sleep-ms 0
                         :timeout-ms 2000
                         :until pred})))

(fn string-from-text [entity]
  (codepoints->text (entity:get-codepoints)))

(fn input-placeholder-updates []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:placeholder "NAME"})
                     ctx-info.ctx))
      (assert (= (string-from-text input.placeholder) "NAME"))
      (input:set-text "ABC")
      (assert (= (string-from-text input.placeholder) ""))
      (input:set-text "")
      (assert (= (string-from-text input.placeholder) "NAME"))
      (input:drop))))

(fn input-context-menu-default-actions []
  (with-pointer-stubs
    (fn [_stubs]
      (local menu (make-menu-manager-stub))
      (with-menu-manager menu
        (fn [_menu]
          (local ctx-info (make-focus-build-ctx _stubs))
          (local input ((Input {:text "alpha"}) ctx-info.ctx))
          (gl.clipboard-set "")
          (input:on-right-click {:point (glm.vec3 1 2 0)
                                 :button 3})
          (local actions (. menu.state.opened :actions))
          (assert (= (length actions) 3) "Input context menu should include 3 default actions")
          (assert (= (. (. actions 1) :name) "Copy"))
          (assert (= (. (. actions 2) :name) "Paste"))
          (assert (= (. (. actions 3) :name) "Clear"))
          ((. (. actions 1) :fn) nil nil)
          (assert (= (gl.clipboard-get) "alpha") "Copy should write full input text to clipboard")
          (input:set-text "ab")
          (input:move-caret-to 1)
          (gl.clipboard-set "Z")
          ((. (. actions 2) :fn) nil nil)
          (assert (= (input:get-text) "aZb") "Paste should insert at cursor position")
          ((. (. actions 3) :fn) nil nil)
          (assert (= (input:get-text) "") "Clear should remove input text")
          (input:drop))))))

(fn input-context-menu-custom-actions []
  (with-pointer-stubs
    (fn [_stubs]
      (local menu (make-menu-manager-stub))
      (with-menu-manager menu
        (fn [_menu]
          (local ctx-info (make-focus-build-ctx _stubs))
          (local input ((Input {:text "alpha"
                                :context-menu (fn [_input _event]
                                                [{:name "Only"
                                                  :fn (fn [_button _event]
                                                        (gl.clipboard-set "custom"))}])})
                       ctx-info.ctx))
          (input:on-right-click {:point (glm.vec3 1 2 0)
                                 :button 3})
          (local actions (. menu.state.opened :actions))
          (assert (= (length actions) 1) "Custom context menu should replace defaults")
          (assert (= (. (. actions 1) :name) "Only"))
          ((. (. actions 1) :fn) nil nil)
          (assert (= (gl.clipboard-get) "custom"))
          (input:drop))))))

(fn input-context-menu-extend-actions []
  (with-pointer-stubs
    (fn [_stubs]
      (local menu (make-menu-manager-stub))
      (with-menu-manager menu
        (fn [_menu]
          (local ctx-info (make-focus-build-ctx _stubs))
          (local input ((Input {:text "alpha"
                                :context-menu (fn [input event]
                                                (local actions (Input.standard-context-menu input event))
                                                (table.insert actions {:name "Extra"
                                                                       :fn (fn [_button _event]
                                                                             (gl.clipboard-set "extra"))})
                                                actions)})
                       ctx-info.ctx))
          (input:on-right-click {:point (glm.vec3 1 2 0)
                                 :button 3})
          (local actions (. menu.state.opened :actions))
          (assert (= (length actions) 4) "Extended context menu should include defaults plus extras")
          (assert (= (. (. actions 1) :name) "Copy"))
          (assert (= (. (. actions 4) :name) "Extra"))
          ((. (. actions 4) :fn) nil nil)
          (assert (= (gl.clipboard-get) "extra"))
          (input:drop))))))

(fn input-registers-double-click []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {}) ctx-info.ctx))
      (assert (= (or (. _stubs.clickables.state :register-double-click) 0) 1)
              "Input should register for double click")
      (input:drop)
      (assert (= (or (. _stubs.clickables.state :unregister-double-click) 0) 1)
              "Input should unregister from double click"))))

(fn input-double-click-external-editor-strips-eof-newline []
  (with-pointer-stubs
    (fn [_stubs]
      (local settings
        {:get-value (fn [key fallback]
                      (if (= key "external-editor.program")
                          "sh"
                          (= key "external-editor.args")
                          ["-c" "printf 'updated\\n' > \"{path}\""]
                          fallback))})
      (with-settings settings
        (fn []
          (local ctx-info (make-focus-build-ctx _stubs))
          (local input ((Input {:text "original"}) ctx-info.ctx))
          (input:on-double-click {})
          (local ok (wait-until (fn [] (= (input:get-text) "updated"))))
          (input:drop)
          (assert ok "single-line input should strip external-editor EOF newline"))))))

(fn input-text-and-insert-states-edit-text []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {}) ctx-info.ctx))
      (local original-states app.states)
      (var transitions [])
      (local stub {:set-state (fn [name]
                                (table.insert transitions name))
                   :active-name (fn [] :text)})
      (set app.states stub)
      (let [(ok result)
            (pcall
              (fn []
                (InputState.connect-input input)
                (local text-state (TextState))
                (local insert-state (InsertState))
                (text-state.on-key-down {:key (string.byte "i")})
                (assert (= input.mode :insert))
                (assert (= (input:get-text) ""))
                (insert-state.on-text-input {:text "i"})
                (insert-state.on-text-input {:text "z"})
                (assert (= (input:get-text) "z"))
                (insert-state.on-key-down {:key 27})
                (assert (= input.mode :normal))
                (assert (= (. transitions 1) :insert))
                (assert (= (. transitions 2) :text))
                (text-state.on-key-down {:key (string.byte "l")})
                (assert (= input.cursor-index 0))))]
        (set app.states original-states)
        (InputState.disconnect-input input)
        (input:drop)
        (when (not ok)
          (error result))))))

(fn with-input-state-spy [body]
  (local original-connect InputState.connect-input)
  (local original-disconnect InputState.disconnect-input)
  (var connect-count 0)
  (var disconnect-count 0)
  (var last-input nil)
  (set InputState.connect-input
       (fn [input]
         (set connect-count (+ connect-count 1))
         (set last-input input)
         (original-connect input)))
  (set InputState.disconnect-input
       (fn [input]
         (set disconnect-count (+ disconnect-count 1))
         (when (= last-input input)
           (set last-input nil))
         (original-disconnect input)))
  (let [(ok result) (pcall body {:connect-count (fn [] connect-count)
                                  :disconnect-count (fn [] disconnect-count)
                                  :last-input (fn [] last-input)})]
    (set InputState.connect-input original-connect)
    (set InputState.disconnect-input original-disconnect)
    (when (not ok)
      (error result))
    result))

(fn input-focus-connects-to-input-state []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (with-input-state-spy
        (fn [spy]
          (local input ((Input {}) ctx-info.ctx))
          (assert (= (spy.connect-count) 0))
          (assert (= (spy.disconnect-count) 0))
          (input.focus-node:request-focus)
          (assert (= (spy.connect-count) 1))
          (assert (= (spy.last-input) input))
          (input:drop)
          (assert (= (spy.disconnect-count) 1)))))))

(fn input-caret-switches-shape-with-mode []
      (with-pointer-stubs
        (fn [_stubs]
          (local ctx-info (make-focus-build-ctx _stubs))
          (local input ((Input {:text "A"}) ctx-info.ctx))
          (input:move-caret-to 0)
          (local measure-caret
                 (fn []
                   (input.layout:measurer)
                   (input.layout:layouter)
                   input.caret.layout.size.x))
          (local font (and input.text input.text.style input.text.style.font))
          (local glyph (and font (fallback-glyph font (. input.codepoints (+ input.cursor-index 1)))))
          (assert font "Input caret test requires a font on the text style")
          (assert glyph "Input caret test requires a fallback glyph")
          (local expected-block (* glyph.advance input.text.style.scale))
          (assert (approx (measure-caret) expected-block))
          (input:enter-insert-mode)
          (assert (approx (measure-caret) input.caret-width))
          (input:drop))))

(fn input-auto-computes-visible-lines-and-columns []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true}) ctx-info.ctx))
      (input.layout:measurer)
      (set input.layout.size (glm.vec3 12 6 0))
      (input.layout:layouter)
      (local padding input.padding)
      (local inner-height (math.max 0 (- input.layout.size.y (* 2 padding.y))))
      (local inner-width (math.max 0 (- input.layout.size.x (* 2 padding.x))))
      (local expected-lines
            (if (> input.line-height 0)
                (math.max input.min-lines
                          (math.min input.max-lines
                                    (math.max 1 (math.floor (/ inner-height input.line-height)))))
                input.min-lines))
      (local expected-columns
            (if (> input.column-width 0)
                (math.max input.min-columns
                          (math.min input.max-columns
                                    (math.max 1 (math.floor (/ inner-width input.column-width)))))
                input.min-columns))
      (assert (= input.visible-line-count expected-lines))
      (assert (= input.visible-column-count expected-columns))
      (input:drop))))

(fn input-scrolls-text-vertically-when-caret-moves []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true
                            :line-count 2
                            :column-count 8}) ctx-info.ctx))
      (input:set-text "alpha\nbeta\ngamma")
      (input.layout:measurer)
      (set input.layout.size (glm.vec3 12 6 0))
      (input.layout:layouter)
      (input:move-caret-to (length input.codepoints))
      (input.layout:layouter)
      (assert (= input.visible-line-count 2))
      (assert (= input.scroll.line 1))
      (assert (= (string-from-text input.text) "beta\ngamma"))
      (input:drop))))

(fn input-scrolls-text-horizontally-when-exceeding-columns []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:column-count 4}) ctx-info.ctx))
      (input:set-text "ABCDEFGH")
      (input.layout:measurer)
      (set input.layout.size (glm.vec3 8 2 0))
      (input.layout:layouter)
      (input:move-caret-to (length input.codepoints))
      (input.layout:layouter)
      (assert (= input.visible-column-count 4))
      (assert (= input.scroll.column 4))
      (assert (= (string-from-text input.text) "EFGH"))
      (input:drop))))

(fn input-caret-move-only-dirties-caret-layout []
  (with-pointer-stubs
    (fn [stubs]
      (local ctx (BuildContext {:clickables stubs.clickables
                                :hoverables stubs.hoverables}))
      (local root (LayoutRoot))
      (local input ((Input {:text "abc" :column-count 5}) ctx))
      (input.layout:set-root root)
      (input.layout:mark-measure-dirty)
      (root:update)
      (input:move-caret-to 0)
      (root:update)
      (input:move-caret 1)
      (assert (= (queue-size root.measure-dirt) 0))
      (assert (. root.layout-dirt.lookup input.caret.layout))
      (assert (not (. root.layout-dirt.lookup input.layout)))
      (assert (not (. root.layout-dirt.lookup input.text.layout)))
      (assert (= (queue-size root.layout-dirt) 1))
      (root:update)
      (input:drop))))

(fn input-scroll-dirties-text-and-caret-layouts []
  (with-pointer-stubs
    (fn [stubs]
      (local ctx (BuildContext {:clickables stubs.clickables
                                :hoverables stubs.hoverables}))
      (local root (LayoutRoot))
      (local input ((Input {:text "ABCDEFGH" :column-count 4}) ctx))
      (input.layout:set-root root)
      (input.layout:mark-measure-dirty)
      (root:update)
      (input:move-caret-to 0)
      (root:update)
      (input:move-caret-to (length input.codepoints))
      (assert (= (queue-size root.measure-dirt) 0))
      (assert (. root.layout-dirt.lookup input.caret.layout))
      (assert (. root.layout-dirt.lookup input.text.layout))
      (assert (= (queue-size root.layout-dirt) 2))
      (root:update)
      (input:drop))))

(local States (require :states))

(fn make-state-tracker []
  (local tracker {:current :normal
                  :transitions [:normal]})
  (local states (States))
  (local original-set states.set-state)
  (states.add-state :normal {:on-enter (fn []
                                         (table.insert tracker.transitions :normal)
                                         (set tracker.current :normal))})
  (states.add-state :text {:on-enter (fn []
                                       (table.insert tracker.transitions :text)
                                       (set tracker.current :text))})
  (states.add-state :insert {:on-enter (fn []
                                         (set tracker.current :insert))})
  (set states.set-state
       (fn [self-or-name maybe-name]
         (local name (if maybe-name maybe-name self-or-name))
         (when name
           (when (not (states:get-state name))
             (states:add-state name {}))
           (local result (original-set name))
           (set tracker.current name)
           result)))
  {:states states
   :tracker tracker})

(fn input-blur-via-click-restores-normal-state []
  (with-pointer-stubs
    (fn [_stubs]
      (local state-info (make-state-tracker))
      (local state-tracker state-info.tracker)
      (local states state-info.states)
      (local original-states app.states)
      (var manager nil)
      (var input nil)
      (let [(ok result)
            (pcall
              (fn []
                (set app.states states)
                (InputState.release-active-input)
                (states:set-state :normal)
                (local ctx-info (make-focus-build-ctx _stubs))
                (set manager ctx-info.manager)
                (set input ((Input {}) ctx-info.ctx))
                (input:on-click {})
                (var text-index nil)
                (each [idx name (ipairs state-tracker.transitions)]
                  (when (and (not text-index) (= name :text))
                    (set text-index idx)))
                (assert text-index
                        (.. "Input should enter text state after click; transitions="
                            (table.concat state-tracker.transitions ",")
                            " current=" (tostring state-tracker.current)))
                (assert (= state-tracker.current :text))
                (manager:clear-focus)
                (var normal-index nil)
                (each [idx name (ipairs state-tracker.transitions)]
                  (when (and (> idx (or text-index 0)) (= name :normal) (not normal-index))
                    (set normal-index idx)))
                (assert normal-index
                        (.. "Input should return to normal after blur; transitions="
                            (table.concat state-tracker.transitions ",")
                            " current=" (tostring state-tracker.current)))
                (assert (= state-tracker.current :normal))
                (assert (not (InputState.active-input)))))]
        (when input
          (input:drop))
        (when manager
          (manager:drop))
        (set app.states original-states)
        (when (not ok)
          (error result))))))

(fn input-blur-returns-to-normal-state []
  (with-pointer-stubs
    (fn [_stubs]
      (local state-info (make-state-tracker))
      (local state-tracker state-info.tracker)
      (local states state-info.states)
      (local original-states app.states)
      (var manager nil)
      (var input nil)
      (let [(ok result)
            (pcall
              (fn []
                (set app.states states)
                (InputState.release-active-input)
                (states:set-state :normal)
                (local ctx-info (make-focus-build-ctx _stubs))
                (set manager ctx-info.manager)
                (set input ((Input {}) ctx-info.ctx))
                (input.focus-node:request-focus)
                (manager:clear-focus)
                (var text-index nil)
                (var normal-index nil)
                (each [idx name (ipairs state-tracker.transitions)]
                  (when (and (not text-index) (= name :text))
                    (set text-index idx))
                  (when (and text-index (> idx text-index) (= name :normal) (not normal-index))
                    (set normal-index idx)))
                (assert text-index
                        (.. "Focused input should enter text state; transitions="
                            (table.concat state-tracker.transitions ",")
                            " current=" (tostring state-tracker.current)))
                (assert normal-index
                        (.. "Focused input blur should return to normal state; transitions="
                            (table.concat state-tracker.transitions ",")
                            " current=" (tostring state-tracker.current)))
                (assert (= state-tracker.current :normal))
                (assert (not (InputState.active-input)))))]
        (when input
          (input:drop))
        (when manager
          (manager:drop))
        (set app.states original-states)
        (when (not ok)
          (error result))))))

(table.insert tests {:name "Input hides placeholder after text entry" :fn input-placeholder-updates})
(table.insert tests {:name "Input context menu default actions" :fn input-context-menu-default-actions})
(table.insert tests {:name "Input context menu custom actions" :fn input-context-menu-custom-actions})
(table.insert tests {:name "Input context menu extend actions" :fn input-context-menu-extend-actions})
(table.insert tests {:name "Input registers for double click" :fn input-registers-double-click})
(table.insert tests {:name "Input external-editor strips eof newline" :fn input-double-click-external-editor-strips-eof-newline})
(table.insert tests {:name "Text and insert states edit input text" :fn input-text-and-insert-states-edit-text})
(table.insert tests {:name "Focused input connects through input state" :fn input-focus-connects-to-input-state})
(table.insert tests {:name "Input blur via click restores normal state" :fn input-blur-via-click-restores-normal-state})
(table.insert tests {:name "Input blur returns to normal state" :fn input-blur-returns-to-normal-state})
(table.insert tests {:name "Input caret switches between block and bar by mode" :fn input-caret-switches-shape-with-mode})
(table.insert tests {:name "Input auto computes visible lines and columns" :fn input-auto-computes-visible-lines-and-columns})
(table.insert tests {:name "Input scrolls vertically to keep caret visible" :fn input-scrolls-text-vertically-when-caret-moves})
(table.insert tests {:name "Input scrolls horizontally when exceeding columns" :fn input-scrolls-text-horizontally-when-exceeding-columns})
(table.insert tests {:name "Input caret move dirties only caret layout" :fn input-caret-move-only-dirties-caret-layout})
(table.insert tests {:name "Input scroll dirties caret and text layouts" :fn input-scroll-dirties-text-and-caret-layouts})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "input"
                       :tests tests})))

{:name "input"
 :tests tests
 :main main}

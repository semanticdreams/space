(local StateBase (require :state-base))
(local InputState (require :input-state-router))

(local SDLK_LEFT 1073741904)
(local SDLK_RIGHT 1073741903)

(local KEY
  {:i (string.byte "i")
   :a (string.byte "a")
   :A (string.byte "A")
   :I (string.byte "I")
   :o (string.byte "o")
   :O (string.byte "O")
   :g (string.byte "g")
   :G (string.byte "G")
   :h (string.byte "h")
   :j (string.byte "j")
   :k (string.byte "k")
   :l (string.byte "l")
   :x (string.byte "x")
   :zero (string.byte "0")
   :dollar (string.byte "$")
   :caret (string.byte "^")})

(local shifted-key-map
  {(string.byte "a") (string.byte "A")
   (string.byte "i") (string.byte "I")
   (string.byte "o") (string.byte "O")
   (string.byte "g") (string.byte "G")
   (string.byte "4") (string.byte "$")
   (string.byte "6") (string.byte "^")})

(fn resolve-key [payload]
  (local key (and payload payload.key))
  (if (and key (StateBase.shift-held? payload))
      (or (. shifted-key-map key) key)
      key))

(local whitespace-codepoints
  (let [table {}]
    (tset table 9 true)
    (tset table 10 true)
    (tset table 11 true)
    (tset table 12 true)
    (tset table 13 true)
    (tset table 32 true)
    table))

(fn whitespace? [codepoint]
  (and codepoint (. whitespace-codepoints codepoint)))

(fn set-state [name]
  (when (and app.engine app.states app.states.set-state)
    (app.states.set-state name)))

(fn active-input []
  (and InputState InputState.active-input (InputState.active-input)))

(fn enter-insert-mode []
  (set-state :insert))

(fn input-model [input]
  (or (and input input.model) input))

(fn input-lines [input]
  (local model (input-model input))
  (and model model.lines))

(fn line-count [lines]
  (if lines
      (length lines)
      0))

(fn clamp-line-index [lines idx]
  (local total (line-count lines))
  (if (<= total 0)
      0
      (math.max 0 (math.min idx (- total 1)))))

(fn line-length [lines idx]
  (local line (and lines (. lines (+ idx 1))))
  (if (and line line.codepoints)
      (length line.codepoints)
      0))

(fn last-valid-column [line-size]
  (if (> (or line-size 0) 0)
      (- line-size 1)
      0))

(fn clamp-column-to-line [line-size column]
  (local limit (last-valid-column line-size))
  (math.max 0 (math.min (or column 0) limit)))

(fn line-start-index [lines idx]
  (var total 0)
  (var i 0)
  (while (< i idx)
    (local line (and lines (. lines (+ i 1))))
    (when line
      (local cp-count (length (or line.codepoints [])))
      (local newline-length (or line.newline-length 0))
      (set total (+ total cp-count newline-length)))
    (set i (+ i 1)))
  total)

(fn line-first-nonblank [line]
  (if (not line)
      0
      (let [codepoints (or line.codepoints [])]
        (var column 0)
        (var found nil)
        (each [_ codepoint (ipairs codepoints)]
          (when (not found)
            (if (whitespace? codepoint)
                (set column (+ column 1))
                (set found column))))
        (or found 0))))

(fn current-line-index [input]
  (local model (input-model input))
  (math.max 0 (or (and model model.cursor-line) 0)))

(fn current-column [input]
  (local model (input-model input))
  (math.max 0 (or (and model model.cursor-column) 0)))

(fn remember-column [input column]
  (if column
      (set input.__preferred-column column)
      (set input.__preferred-column (current-column input)))
  input.__preferred-column)

(fn preferred-column [input]
  (or input.__preferred-column (current-column input)))

(fn move-to-line-column [input line-index column]
  (local lines (input-lines input))
  (local model (input-model input))
  (if (not lines)
      (let [codepoints (or (and model model.codepoints) [])
            total (length codepoints)
            clamped (clamp-column-to-line total column)
            moved (input:move-caret-to clamped)]
        (remember-column input clamped)
        moved)
      (let [total (line-count lines)]
        (if (<= total 0)
            (let [moved (input:move-caret-to 0)]
              (remember-column input 0)
              moved)
            (let [clamped (clamp-line-index lines line-index)
                  line-size (line-length lines clamped)
                  clamped-column (clamp-column-to-line line-size column)
                  start (line-start-index lines clamped)
                  target (+ start clamped-column)
                  moved (input:move-caret-to target)]
              (remember-column input clamped-column)
              moved)))))

(fn move-to-line-edge [input edge]
  (local lines (input-lines input))
  (if (not lines)
      (let [model (input-model input)
            codepoints (or (and model model.codepoints) [])
            column (if (= edge :start)
                       0
                       (last-valid-column (length codepoints)))]
        (move-to-line-column input 0 column))
      (let [current (clamp-line-index lines (current-line-index input))
            line-size (line-length lines current)
            column (if (= edge :start)
                       0
                       (last-valid-column line-size))]
        (move-to-line-column input current column))))

(fn move-to-first-nonblank [input]
  (local lines (input-lines input))
  (if (not lines)
      (move-to-line-edge input :start)
      (let [current (clamp-line-index lines (current-line-index input))
            line (. lines (+ current 1))
            column (line-first-nonblank line)]
        (move-to-line-column input current column))))

(fn move-to-first-line [input]
  (remember-column input nil)
  (move-to-line-column input 0 0))

(fn move-to-last-line [input]
  (remember-column input nil)
  (local lines (input-lines input))
  (local total (line-count lines))
  (if (<= total 0)
      false
      (move-to-line-column input (- total 1) (preferred-column input))))

(fn move-horizontal [input delta]
  (local model (input-model input))
  (local lines (input-lines input))
  (if (or (not model) (not lines))
      (input:move-caret delta)
      (let [column (math.max 0 (or model.cursor-column 0))
            line-index (math.max 0 (or model.cursor-line 0))
            line-size (line-length lines line-index)
            max-column (last-valid-column line-size)]
        (if (< delta 0)
            (if (> column 0)
                (let [moved (input:move-caret delta)]
                  (when moved
                    (remember-column input nil))
                  moved)
                false)
            (if (and (> line-size 0)
                     (< column max-column))
                (let [moved (input:move-caret delta)]
                  (when moved
                    (remember-column input nil))
                  moved)
                false)))))

(fn move-vertical [input delta]
  (remember-column input nil)
  (local lines (input-lines input))
  (if (not lines)
      false
      (let [total (line-count lines)]
        (if (<= total 0)
            false
            (let [current (clamp-line-index lines (current-line-index input))
                  target (math.max 0 (math.min (+ current delta) (- total 1)))]
              (if (= target current)
                  false
                  (move-to-line-column input target (preferred-column input))))))))

(fn clamp-caret-to-current-line [input]
  (local lines (input-lines input))
  (if (not lines)
      (move-to-line-column input 0 (current-column input))
      (let [current-line (clamp-line-index lines (current-line-index input))
            column (current-column input)
            line-size (line-length lines current-line)
            clamped (clamp-column-to-line line-size column)]
        (if (= column clamped)
            false
            (move-to-line-column input current-line clamped)))))

(fn enter-insert-state [input]
  (input:enter-insert-mode)
  (StateBase.ignore-next-text-input)
  (enter-insert-mode)
  true)

(fn open-line-below [input]
  (if (not (= input.multiline? true))
      false
      (do
        (move-to-line-edge input :end)
        (input:move-caret 1)
        (input:insert-text "\n")
        (remember-column input 0)
        (enter-insert-state input))))

(fn open-line-above [input]
  (if (not (= input.multiline? true))
      false
      (let [lines (input-lines input)]
        (if (not lines)
            false
            (let [current (clamp-line-index lines (current-line-index input))
                  start (line-start-index lines current)]
              (input:move-caret-to start)
              (input:insert-text "\n")
              (input:move-caret-to start)
              (remember-column input 0)
              (enter-insert-state input))))))

(fn command-enter-insert [input _state]
  (enter-insert-state input))

(fn command-insert-after [input _state]
  (input:move-caret 1)
  (enter-insert-state input))

(fn command-append-line-end [input _state]
  (move-to-line-edge input :end)
  (input:move-caret 1)
  (enter-insert-state input))

(fn command-insert-line-start [input _state]
  (move-to-first-nonblank input)
  (enter-insert-state input))

(fn command-open-line-below [input _state]
  (open-line-below input))

(fn command-open-line-above [input _state]
  (open-line-above input))

(fn command-go-last-line [input _state]
  (move-to-last-line input))

(fn command-go-first-line [input _state]
  (move-to-first-line input))

(fn command-move-horizontal [delta]
  (fn [input _state]
    (move-horizontal input delta)))

(fn command-move-vertical [delta]
  (fn [input _state]
    (move-vertical input delta)))

(fn command-line-edge [edge]
  (fn [input _state]
    (move-to-line-edge input edge)))

(fn command-first-nonblank [input _state]
  (move-to-first-nonblank input))

(fn command-delete-forward [input _state]
  (local removed (input:delete-at-cursor))
  (when removed
    (clamp-caret-to-current-line input))
  removed)

(fn make-default-keymap []
  (local move-left (command-move-horizontal -1))
  (local move-right (command-move-horizontal 1))
  (local move-down (command-move-vertical 1))
  (local move-up (command-move-vertical -1))
  (local line-start (command-line-edge :start))
  (local line-end (command-line-edge :end))
  (local keymap {})
  (fn bind [target key binding]
    (tset target key binding))
  (bind keymap KEY.i {:handler command-enter-insert})
  (bind keymap KEY.a {:handler command-insert-after})
  (bind keymap KEY.A {:handler command-append-line-end})
  (bind keymap KEY.I {:handler command-insert-line-start})
  (bind keymap KEY.o {:handler command-open-line-below})
  (bind keymap KEY.O {:handler command-open-line-above})
  (local g-map {})
  (bind g-map KEY.g {:handler command-go-first-line})
  (bind keymap KEY.g {:next g-map})
  (bind keymap KEY.G {:handler command-go-last-line})
  (bind keymap KEY.h {:handler move-left})
  (bind keymap KEY.l {:handler move-right})
  (bind keymap KEY.j {:handler move-down})
  (bind keymap KEY.k {:handler move-up})
  (bind keymap KEY.zero {:handler line-start})
  (bind keymap KEY.dollar {:handler line-end})
  (bind keymap KEY.caret {:handler command-first-nonblank})
  (bind keymap KEY.x {:handler command-delete-forward})
  (bind keymap SDLK_LEFT {:handler move-left})
  (bind keymap SDLK_RIGHT {:handler move-right})
  keymap)

(fn binding-handler [binding]
  (if (= (type binding) "table")
      binding.handler
      (if (= (type binding) "function")
          binding
          nil)))

(fn binding-next [binding]
  (and (= (type binding) "table") binding.next))

(fn apply-binding [state input binding]
  (local next (binding-next binding))
  (if next
      (do
        (set state.pending-keymap next)
        true)
      (let [handler (binding-handler binding)]
        (set state.pending-keymap nil)
        (if handler
            (handler input state)
            false))))

(fn resolve-binding [state key]
  (local keymap (or state.pending-keymap state.keymap))
  (local binding (and keymap (. keymap key)))
  (if binding
      binding
      (if state.pending-keymap
          (do
            (set state.pending-keymap nil)
            (resolve-binding state key))
          nil)))

(fn handle-key-command [state input key]
  (local binding (resolve-binding state key))
  (if binding
      (apply-binding state input binding)
      false))

(fn handle-text-key [state payload]
  (local input (active-input))
  (if (not input)
      false
      (do
        (clamp-caret-to-current-line input)
        (let [key (resolve-key payload)]
          (if (not key)
              false
              (handle-key-command state input key))))))

(fn on-key-down [state payload]
  (if (handle-text-key state payload)
      true
      (if (StateBase.handle-focus-tab payload)
          true
          (if (active-input)
              true
              (and app.first-person-controls
                   (app.first-person-controls:on-key-down payload))))))

(fn sync-mode []
  (local input (active-input))
  (when input
    (input:enter-normal-mode)))

(fn TextState []
  (var state nil)
  (set state
       (StateBase.make-state {:name :text
                              :on-key-down (fn [payload]
                                             (on-key-down state payload))
                              :on-enter (fn []
                                          (when state
                                            (set state.pending-keymap nil))
                                          (sync-mode))}))
  (set state.keymap (make-default-keymap))
  (set state.pending-keymap nil)
  state)

TextState

(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local {: Layout} (require :layout))
(local Button (require :button))
(local Card (require :card))
(local DepthCuboid (require :depth-cuboid))
(local Padding (require :padding))
(local Rectangle (require :rectangle))
(local Text (require :text))
(local WidgetCuboid (require :widget-cuboid))
(local TetrisGame (require :tetris-game))
(local TetrisStateRouter (require :tetris-state-router))

(local SDLK_LEFT 1073741904)
(local SDLK_RIGHT 1073741903)
(local SDLK_UP 1073741906)
(local SDLK_DOWN 1073741905)
(local SDLK_SPACE 32)

(local default-cell-size 1.0)
(local board-background (glm.vec4 0.08 0.08 0.1 1))
(local panel-background (glm.vec4 0.12 0.12 0.16 1))
(local titlebar-background (glm.vec4 0.18 0.18 0.2 1))

(local block-colors
  {:I (glm.vec4 0.2 0.8 0.9 1)
   :O (glm.vec4 0.95 0.8 0.2 1)
   :T (glm.vec4 0.7 0.4 0.9 1)
   :S (glm.vec4 0.3 0.8 0.4 1)
   :Z (glm.vec4 0.9 0.3 0.35 1)
   :J (glm.vec4 0.3 0.4 0.9 1)
   :L (glm.vec4 0.95 0.55 0.2 1)})

(fn darken [color factor]
  (local f (or factor 0.65))
  (glm.vec4 (* color.x f) (* color.y f) (* color.z f) color.w))

(fn resolve-block-color [id]
  (or (. block-colors id) (glm.vec4 0.7 0.7 0.7 1)))

(fn make-block [opts]
  (local options (or opts {}))
  (local base-color (resolve-block-color options.id))
  (local front (Rectangle {:color base-color}))
  (local cube-builder
    (WidgetCuboid {:child front
                   :side-color (darken base-color)
                   :depth-scale 1.0
                   :min-depth 0}))
  (fn build [ctx]
    (local cube (cube-builder ctx))
    (local faces (and cube.cuboid cube.cuboid.faces))
    (local side-faces [])
    (when faces
      (each [i face (ipairs faces)]
        (when (> i 1)
          (table.insert side-faces face))))

    (fn apply-visible [visible?]
      (when front
        (front:set-visible visible? {:mark-layout-dirty? false}))
      (each [_ face (ipairs side-faces)]
        (face:set-visible visible? {:mark-layout-dirty? false})))

    (fn apply-color [color]
      (local side-color (darken color))
      (when front
        (set front.color color)
        (when front.layout
          (front.layout:mark-layout-dirty)))
      (each [_ face (ipairs side-faces)]
        (set face.color side-color)
        (when face.layout
          (face.layout:mark-layout-dirty))))

    (set cube.set-visible (fn [_self visible?] (apply-visible visible?)))
    (set cube.set-color (fn [_self color] (apply-color color)))
    (set cube.block-color base-color)
    cube))

(fn build-tetris-board [ctx options game cell-size width height]
  (local clickables (assert ctx.clickables "TetrisBoard requires ctx.clickables"))
  (local hoverables (assert ctx.hoverables "TetrisBoard requires ctx.hoverables"))
  (local focus-context (and ctx ctx.focus))
  (local focusable? (and focus-context (not (= options.focusable? false))))
  (local focus-node
    (and focusable?
         (focus-context:create-node {:name (or options.focus-name options.name "tetris-board")})))
  (local focus-manager (and focus-node focus-node.manager))
  (local background ((Rectangle {:color board-background}) ctx))
  (local blocks [])

  (for [y 1 height]
    (local row [])
    (set (. blocks y) row)
    (for [x 1 width]
      (local block-builder (make-block {}))
      (local block (block-builder ctx))
      (block:set-visible false)
      (tset row x block)))

  (fn update-blocks []
    (each [row block-row (ipairs blocks)]
      (each [_ block (ipairs block-row)]
        (block:set-visible false)))
    (each [_ cell (ipairs (game:cells))]
      (local row (. blocks cell.y))
      (when row
        (local block (. row cell.x))
        (when block
          (local color (resolve-block-color cell.id))
          (block:set-color color)
          (block:set-visible true)))))

  (fn handle-key [self payload]
    (local key (and payload payload.key))
    (if (not key)
        false
        (let [recognized? (or (= key SDLK_LEFT)
                              (= key SDLK_RIGHT)
                              (= key SDLK_DOWN)
                              (= key SDLK_UP)
                              (= key SDLK_SPACE))]
          (when (= key SDLK_LEFT)
            (game:move -1 0))
          (when (= key SDLK_RIGHT)
            (game:move 1 0))
          (when (= key SDLK_DOWN)
            (game:soft-drop))
          (when (= key SDLK_UP)
            (game:rotate))
          (when (= key SDLK_SPACE)
            (game:hard-drop))
          (when recognized?
            (update-blocks))
          recognized?)))

  (fn handle-pause [_self _payload]
    (game:pause)
    (when options.on-status
      (options.on-status)))

  (var board nil)
  (var focused? false)

  (fn apply-focus [focused]
    (when (not (= focused focused?))
      (set focused? focused)
      (if focused?
          (do
            (TetrisStateRouter.connect-board board)
            (when options.on-status
              (options.on-status)))
          (do
            (game:pause)
            (TetrisStateRouter.disconnect-board board)
            (when options.on-status
              (options.on-status))))))

  (local layout
    (Layout {:name (or options.name "tetris-board")
             :children
             (let [children [background.layout]]
               (each [_ row (ipairs blocks)]
                 (each [_ block (ipairs row)]
                   (table.insert children block.layout)))
               children)
             :measurer (fn [self]
                         (set self.measure (glm.vec3 (* width cell-size)
                                                 (* height cell-size)
                                                 cell-size)))
             :layouter
             (fn [self]
               (local size (glm.vec3 (* width cell-size)
                                     (* height cell-size)
                                     (. self.size 3)))
               (set background.layout.size size)
               (set background.layout.position self.position)
               (set background.layout.rotation self.rotation)
               (set background.layout.depth-offset-index self.depth-offset-index)
               (set background.layout.clip-region self.clip-region)
               (background.layout:layouter)
               (each [row block-row (ipairs blocks)]
                 (each [col block (ipairs block-row)]
                   (local x (* (- col 1) cell-size))
                   (local y (* (- row 1) cell-size))
                   (local pos (+ self.position (self.rotation:rotate (glm.vec3 x y 0))))
                   (set block.layout.size (glm.vec3 cell-size cell-size cell-size))
                   (set block.layout.position pos)
                   (set block.layout.rotation self.rotation)
                   (set block.layout.depth-offset-index (+ self.depth-offset-index 1))
                   (set block.layout.clip-region self.clip-region)
                   (block.layout:layouter))))}))
  (when (and focus-node focus-context layout)
    (focus-context:attach-bounds focus-node {:layout layout}))

  (set board
    {:layout layout
     :background background
     :blocks blocks
     :focus-node focus-node
     :focus-manager focus-manager
     :pointer-target (and ctx ctx.pointer-target)
     :on-key-down handle-key
     :on-pause handle-pause
     :sync update-blocks})

  (set board.request-focus
       (fn [self]
         (when self.focus-node
           (self.focus-node:request-focus))))
  (set board.on-click
       (fn [self _event]
         (self:request-focus)))
  (set board.intersect
       (fn [self ray]
         (self.layout:intersect ray)))

  (clickables:register board)
  (hoverables:register board)

  (when focus-manager
    (set board.__focus-focus-listener
         (focus-manager.focus-focus.connect
           (fn [event]
             (when (and event (= event.current focus-node))
               (apply-focus true)))))
    (set board.__focus-blur-listener
         (focus-manager.focus-blur.connect
           (fn [event]
             (when (and event (= event.previous focus-node))
               (apply-focus false))))))
  (when (and focus-manager focus-node (= (focus-manager:get-focused-node) focus-node))
    (apply-focus true))
  (update-blocks)

  (set board.drop
       (fn [self]
         (clickables:unregister self)
         (hoverables:unregister self)
         (TetrisStateRouter.disconnect-board self)
         (when self.__focus-focus-listener
           (local manager self.focus-manager)
           (when (and manager manager.focus-focus)
             (manager.focus-focus.disconnect self.__focus-focus-listener true))
           (set self.__focus-focus-listener nil))
         (when self.__focus-blur-listener
           (local manager self.focus-manager)
           (when (and manager manager.focus-blur)
             (manager.focus-blur.disconnect self.__focus-blur-listener true))
           (set self.__focus-blur-listener nil))
         (when self.focus-node
           (self.focus-node:drop)
           (set self.focus-node nil))
         (self.background:drop)
         (each [_ row (ipairs self.blocks)]
           (each [_ block (ipairs row)]
             (block:drop)))
         (self.layout:drop)))
  board)

(fn TetrisBoard [opts]
  (local options (or opts {}))
  (local game (assert options.game "TetrisBoard requires :game"))
  (local cell-size (or options.cell-size default-cell-size))
  (local width (or game.width 10))
  (local height (or game.height 20))
  (fn build [ctx]
    (build-tetris-board ctx options game cell-size width height))
  build)

(fn status-text [game]
  (if game.game-over?
      (string.format "Status: Game Over | Lines: %d | Score: %d" game.lines-cleared game.score)
      (if game.running?
          (string.format "Status: Running | Lines: %d | Score: %d" game.lines-cleared game.score)
          (string.format "Status: Paused | Lines: %d | Score: %d" game.lines-cleared game.score))))

(fn make-titlebar [opts]
  (local title (or opts.title "Tetris"))
  (local on-close opts.on-close)
  (local title-row
    (Flex {:axis 1
           :xspacing 0.4
           :yalign :center
           :children
           [(FlexChild (Text {:text title}) 1)
            (FlexChild (Button {:icon "close"
                                :variant :tertiary
                                :padding [0.3 0.3]
                                :on-click (fn [_button _event]
                                            (when on-close
                                              (on-close)))}))]}))
  (DepthCuboid {:child (Card {:color titlebar-background
                              :child (Padding {:edge-insets [0.4 0.35]
                                               :child title-row})})}))

(fn build-tetris-dialog [ctx options]
  (local game (TetrisGame (or options.game {})))
  (var status-text-entity nil)

  (fn update-status []
    (when status-text-entity
      (status-text-entity:set-text (status-text game))))

  (local board-builder
    (TetrisBoard {:game game
                  :cell-size (or options.cell-size default-cell-size)
                  :name "tetris-board"
                  :on-status update-status}))
  (local board (board-builder ctx))

  (local start-button
    (Button {:text "Start"
             :variant :primary
             :padding [0.4 0.35]
             :on-click (fn [_button _event]
                         (game:start)
                         (board:request-focus)
                         (board:sync)
                         (update-status))}))
  (local stop-button
    (Button {:text "Stop"
             :variant :secondary
             :padding [0.4 0.35]
             :on-click (fn [_button _event]
                         (game:pause)
                         (update-status))}))
  (local status-builder
    (fn [child-ctx]
      (set status-text-entity ((Text {:text (status-text game)}) child-ctx))
      status-text-entity))
  (local control-row
    (Flex {:axis 1
           :xspacing 0.5
           :yalign :center
           :children
           [(FlexChild start-button 0)
            (FlexChild stop-button 0)
            (FlexChild status-builder 1)]}))
  (local control-panel
    (DepthCuboid
      {:child
       (Card {:color panel-background
              :child (Padding {:edge-insets [0.5 0.35]
                               :child control-row})})}))

  (local titlebar (make-titlebar {:title (or options.title "Tetris")
                                  :on-close options.on-close}))
  (local content
    (Flex {:axis 2
           :xalign :stretch
           :zalign :stretch
           :yspacing 0.4
           :children
           [(FlexChild titlebar 0)
            (FlexChild control-panel 0)
            (FlexChild board 0)]}))

  (var update-handler nil)
  (when (and app.engine app.engine.events app.engine.events.updated)
    (set update-handler
         (app.engine.events.updated:connect
           (fn [delta]
             (game:update delta)
             (board:sync)
             (update-status)))))

  (set content.game game)
  (set content.board board)
  (local base-drop content.drop)
  (set content.drop
       (fn [self]
         (when (and update-handler app.engine app.engine.events app.engine.events.updated)
           (app.engine.events.updated:disconnect update-handler true))
         (base-drop self)))
  content)

(fn TetrisDialog [opts]
  (local options (or opts {}))
  (fn build [ctx]
    (build-tetris-dialog ctx options))
  build)

(local exports {:TetrisDialog TetrisDialog
                :TetrisBoard TetrisBoard})

(setmetatable exports {:__call (fn [_ ...] (TetrisDialog ...))})

exports

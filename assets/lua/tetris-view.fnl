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
(local DeepDialog (require :deep-dialog))

(local SDLK_LEFT 1073741904)
(local SDLK_RIGHT 1073741903)
(local SDLK_UP 1073741906)
(local SDLK_DOWN 1073741905)
(local SDLK_SPACE 32)

(local default-cell-size 1.0)
(local board-background (glm.vec4 0.08 0.08 0.1 1))
(local panel-background (glm.vec4 0.12 0.12 0.16 1))

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
  (local front-builder (Rectangle {:color base-color}))
  (local cube-builder
    (WidgetCuboid {:child front-builder
                   :side-color (darken base-color)
                   :depth-scale 1.0
                   :min-depth 0}))
  (fn resolve-side-face [face]
    (if (and face face.set-visible)
        face
        (and face face.child face.child.set-visible face.child)))
  (fn collect-side-faces [faces]
    (local out [])
    (when faces
      (each [i face (ipairs faces)]
        (when (> i 1)
          (local target (resolve-side-face face))
          (when target
            (table.insert out target)))))
    out)
  (fn build [ctx]
    (local cube (cube-builder ctx))
    (local front (or cube.front (and cube.cuboid cube.cuboid.__front_widget)))
    (local faces (and cube.cuboid cube.cuboid.faces))
    (local side-faces (collect-side-faces faces))

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
        (do
          (local recognized?
            (or (= key SDLK_LEFT)
                (= key SDLK_RIGHT)
                (= key SDLK_DOWN)
                (= key SDLK_UP)
                (= key SDLK_SPACE)))
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
             (do
               (local children [background.layout])
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
  (local status-label
    (if game.game-over?
        "Game Over"
        (if game.running?
            "Running"
            "Paused")))
  (string.format "Status: %s\nLines: %d\nScore: %d"
                 status-label
                 game.lines-cleared
                 game.score))

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
  (var board nil)
  (local board-capture-builder
    (fn [child-ctx]
      (set board (board-builder child-ctx))
      board))

  (var update-handler nil)

  (fn disconnect-updates []
    (when (and update-handler app.engine app.engine.events app.engine.events.updated)
      (app.engine.events.updated:disconnect update-handler true)
      (set update-handler nil)))

  (fn on-update [delta]
    (when (game:update delta)
      (board:sync)
      (update-status)
      (when (or game.game-over? (not game.running?))
        (disconnect-updates))))

  (fn connect-updates []
    (when (and (not update-handler) app.engine app.engine.events app.engine.events.updated)
      (set update-handler (app.engine.events.updated:connect on-update))))

  ;; Tetris dialog owns the update loop subscription: connect only while running.
  (local base-start game.start)
  (set game.start
       (fn [self]
         (base-start self)
         (connect-updates)))
  (local base-pause game.pause)
  (set game.pause
       (fn [self]
         (base-pause self)
         (disconnect-updates)))

  (local start-button
    (Button {:text "Start"
             :variant :primary
             :padding [0.4 0.35]
             :on-click (fn [_button _event]
                         (game:start)
                         (assert board "tetris start requires board")
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
  (local button-row
    (Flex {:axis 1
           :xspacing 0.5
           :yalign :center
           :children [(FlexChild start-button 0)
                      (FlexChild stop-button 0)]}))
  (local side-panel-content
    (Flex {:axis 2
           :xalign :stretch
           :yspacing 0.4
           :children [(FlexChild button-row 0)
                      (FlexChild status-builder 0)]}))
  (local side-panel
    (DepthCuboid
      {:child
       (Card {:color panel-background
              :child (Padding {:edge-insets [0.5 0.35]
                               :child side-panel-content})})}))

  (local body-builder
    (Flex {:axis 1
           :xspacing 0
           :xalign :stretch
           :yalign :stretch
           :zalign :stretch
           :children
           [(FlexChild board-capture-builder 0)
            (FlexChild side-panel 0)]}))

  (local dialog-builder
    (DeepDialog {:title (or options.title "Tetris")
                 :body-padding [0 0]
                 :child body-builder
                 :on-close options.on-close}))
  (local content (dialog-builder ctx))
  (assert board "TetrisDialog build requires board entity")

  (set content.game game)
  (set content.board board)
  (set content.status_text status-text-entity)
  (set content.update_status update-status)
  (local base-drop content.drop)
  (set content.drop
       (fn [self]
         (disconnect-updates)
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

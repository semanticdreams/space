(local pieces
  [{:id :I
    :rotations
    [[[0 0] [1 0] [2 0] [3 0]]
     [[0 0] [0 1] [0 2] [0 3]]
     [[0 0] [1 0] [2 0] [3 0]]
     [[0 0] [0 1] [0 2] [0 3]]]}
   {:id :O
    :rotations
    [[[0 0] [1 0] [0 1] [1 1]]
     [[0 0] [1 0] [0 1] [1 1]]
     [[0 0] [1 0] [0 1] [1 1]]
     [[0 0] [1 0] [0 1] [1 1]]]}
   {:id :T
    :rotations
    [[[0 0] [1 0] [2 0] [1 1]]
     [[0 0] [0 1] [0 2] [1 1]]
     [[0 1] [1 1] [2 1] [1 0]]
     [[1 0] [1 1] [1 2] [0 1]]]}
   {:id :S
    :rotations
    [[[1 0] [2 0] [0 1] [1 1]]
     [[0 0] [0 1] [1 1] [1 2]]
     [[1 0] [2 0] [0 1] [1 1]]
     [[0 0] [0 1] [1 1] [1 2]]]}
   {:id :Z
    :rotations
    [[[0 0] [1 0] [1 1] [2 1]]
     [[1 0] [0 1] [1 1] [0 2]]
     [[0 0] [1 0] [1 1] [2 1]]
     [[1 0] [0 1] [1 1] [0 2]]]}
   {:id :J
    :rotations
    [[[0 0] [0 1] [1 1] [2 1]]
     [[0 0] [1 0] [0 1] [0 2]]
     [[0 0] [1 0] [2 0] [2 1]]
     [[1 0] [1 1] [1 2] [0 2]]]}
   {:id :L
    :rotations
    [[[2 0] [0 1] [1 1] [2 1]]
     [[0 0] [0 1] [0 2] [1 2]]
     [[0 0] [1 0] [2 0] [0 1]]
     [[0 0] [1 0] [1 1] [1 2]]]}])

(fn copy-sequence [sequence]
  (if sequence
      (do
        (local entries [])
        (each [_ entry (ipairs sequence)]
          (table.insert entries entry))
        entries)
      []))

(fn piece-by-id [id]
  (accumulate [result nil _ piece (ipairs pieces)]
    (if (= piece.id id)
        piece
        result)))

(fn random-piece-id []
  (local idx (math.random (length pieces)))
  (. (. pieces idx) :id))

(fn make-empty-row [width]
  (local row [])
  (for [_ 1 width]
    (table.insert row false))
  row)

(fn make-grid [width height]
  (local grid [])
  (for [_ 1 height]
    (table.insert grid (make-empty-row width)))
  grid)

(fn cell-x [cell] (or (. cell 1) 0))
(fn cell-y [cell] (or (. cell 2) 0))

(fn rotation-cells [piece rotation]
  (local rotations (or (and piece piece.rotations) []))
  (local index (math.max 1 (math.min (or rotation 1) (length rotations))))
  (or (. rotations index) []))

(fn cells-fit? [grid width height piece rotation origin-x origin-y]
  (local cells (rotation-cells piece rotation))
  (var fits true)
  (each [_ cell (ipairs cells)]
    (when fits
      (local x (+ origin-x (cell-x cell)))
      (local y (+ origin-y (cell-y cell)))
      (if (or (< x 1) (> x width) (< y 1) (> y height))
          (set fits false)
          (when (. (. grid y) x)
            (set fits false)))))
  fits)

(fn piece-bounds [piece rotation]
  (local cells (rotation-cells piece rotation))
  (var max-x 0)
  (var max-y 0)
  (each [_ cell (ipairs cells)]
    (local x (cell-x cell))
    (local y (cell-y cell))
    (when (> x max-x) (set max-x x))
    (when (> y max-y) (set max-y y)))
  {:width (+ max-x 1)
   :height (+ max-y 1)})

(fn clear-lines [grid width height]
  (local remaining [])
  (var cleared 0)
  (each [_ row (ipairs grid)]
    (var filled? true)
    (for [i 1 width]
      (when (not (. row i))
        (set filled? false)))
    (if filled?
        (set cleared (+ cleared 1))
        (table.insert remaining row)))
  (while (< (length remaining) height)
    (table.insert remaining (make-empty-row width)))
  {:grid remaining
   :cleared cleared})

(fn spawn-position [width height piece rotation]
  (local bounds (piece-bounds piece rotation))
  (local start-x (+ 1 (math.floor (/ (- width bounds.width) 2))))
  (local start-y (+ 1 (- height bounds.height)))
  {:x start-x :y (math.max 1 start-y)})

(fn collect-board-cells [state]
  (local cells [])
  (each [y row (ipairs state.grid)]
    (each [x value (ipairs row)]
      (when value
        (table.insert cells {:x x :y y :id value :active? false}))))
  (local active state.active)
  (when active
    (local piece (piece-by-id active.id))
    (local rotation (or active.rotation 1))
    (local origin-x (or active.x 1))
    (local origin-y (or active.y 1))
    (each [_ cell (ipairs (rotation-cells piece rotation))]
      (table.insert cells {:x (+ origin-x (cell-x cell))
                           :y (+ origin-y (cell-y cell))
                           :id active.id
                           :active? true})))
  cells)

(fn build-tetris-game [opts]
  (local options (or opts {}))
  (local width (or options.width 10))
  (local height (or options.height 20))
  ; Engine frame delta is in milliseconds (see Timer::computeDeltaTime).
  (local drop-interval (or options.drop-interval 600))
  (local sequence (copy-sequence options.sequence))

  (fn next-piece [self]
    (if (> (length self.sequence) 0)
        (table.remove self.sequence 1)
        (random-piece-id)))

  (fn spawn-piece [self]
    (local id (next-piece self))
    (local piece (piece-by-id id))
    (local rotation 1)
    (local start (spawn-position self.width self.height piece rotation))
    (if (cells-fit? self.grid self.width self.height piece rotation start.x start.y)
        (set self.active {:id id :rotation rotation :x start.x :y start.y})
        (do
          (set self.active nil)
          (set self.running? false)
          (set self.paused? true)
          (set self.game-over? true))))

  (fn reset-game [self]
    (set self.grid (make-grid self.width self.height))
    (set self.active nil)
    (set self.running? false)
    (set self.paused? true)
    (set self.game-over? false)
    (set self.lines-cleared 0)
    (set self.score 0)
    (set self.drop-timer 0)
    (spawn-piece self))

  (fn start-game [self]
    (when self.game-over?
      (reset-game self))
    (when (not self.active)
      (spawn-piece self))
    (if self.game-over?
        (do
          (set self.running? false)
          (set self.paused? true))
        (do
          (set self.running? true)
          (set self.paused? false))))

  (fn pause-game [self]
    (set self.running? false)
    (set self.paused? true))

  (fn stamp-cell [self id x y]
    (when (and (>= x 1) (<= x self.width) (>= y 1) (<= y self.height))
      (local row (. self.grid y))
      (when row
        (tset row x id))))

  (fn stamp-active-cells [self active]
    (local piece (piece-by-id active.id))
    (each [_ cell (ipairs (rotation-cells piece active.rotation))]
      (local x (+ active.x (cell-x cell)))
      (local y (+ active.y (cell-y cell)))
      (stamp-cell self active.id x y)))

  (fn apply-line-clear [self]
    (local cleared (clear-lines self.grid self.width self.height))
    (set self.grid cleared.grid)
    (when (> cleared.cleared 0)
      (set self.lines-cleared (+ self.lines-cleared cleared.cleared))
      (set self.score (+ self.score (* cleared.cleared cleared.cleared 100)))))

  (fn finalize-lock [self active]
    (when active
      (stamp-active-cells self active))
    (apply-line-clear self)
    (spawn-piece self))

  (fn lock-piece [self]
    (finalize-lock self self.active))

  (fn move-active [self dx dy]
    (local active self.active)
    (if (not active)
        false
        (do
          (local piece (piece-by-id active.id))
          (local next-x (+ active.x (or dx 0)))
          (local next-y (+ active.y (or dy 0)))
          (if (cells-fit? self.grid self.width self.height piece active.rotation next-x next-y)
              (do
                (set active.x next-x)
                (set active.y next-y)
                true)
              false))))

  (fn rotate-active [self]
    (local active self.active)
    (if (not active)
        false
        (do
          (local piece (piece-by-id active.id))
          (local next-rotation (+ (or active.rotation 1) 1))
          (local rotation (if (> next-rotation 4) 1 next-rotation))
          (if (cells-fit? self.grid self.width self.height piece rotation active.x active.y)
              (do
                (set active.rotation rotation)
                true)
              false))))

  (fn soft-drop [self]
    (if (move-active self 0 -1)
        true
        (do
          (lock-piece self)
          true)))

  (fn hard-drop [self]
    (var moved false)
    (while (move-active self 0 -1)
      (set moved true))
    (lock-piece self)
    moved)

  (fn update-game [self delta]
    (if (and self.running? (not self.paused?) (not self.game-over?))
        (do
          (set self.drop-timer (+ (or self.drop-timer 0) (or delta 0)))
          (var changed? false)
          (while (>= self.drop-timer self.drop-interval)
            (set self.drop-timer (- self.drop-timer self.drop-interval))
            (soft-drop self)
            (set changed? true))
          changed?)
        false))

  {:width width
   :height height
   :grid (make-grid width height)
   :active nil
   :running? false
   :paused? true
   :game-over? false
   :lines-cleared 0
   :score 0
   :drop-interval drop-interval
   :drop-timer 0
   :sequence sequence
   :start start-game
   :pause pause-game
   :reset reset-game
   :move move-active
   :rotate rotate-active
   :soft-drop soft-drop
   :hard-drop hard-drop
   :update update-game
   :cells collect-board-cells})

(fn TetrisGame [opts]
  (build-tetris-game (or opts {})))

TetrisGame

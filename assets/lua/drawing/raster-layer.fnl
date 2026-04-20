(local fs (require :fs))
(local ImageIO (require :image-io))

(local default-tile-size 128)
(local channels 4)

(fn clamp [value min-value max-value]
  (math.max min-value
            (math.min max-value value)))

(fn floor-div [value size]
  (math.floor (/ value size)))

(fn round-int [value]
  (math.floor (+ value 0.5)))

(fn tile-key [tx ty]
  (.. (tostring tx) ":" (tostring ty)))

(fn parse-tile-key [key]
  (local (tx-str ty-str) (string.match key "^(-?%d+):(-?%d+)$"))
  (assert (and tx-str ty-str) (.. "RasterLayer invalid tile key: " key))
  {:tx (tonumber tx-str)
   :ty (tonumber ty-str)})

(fn blank-bytes [tile-size]
  (local count (* tile-size tile-size channels))
  (local out {})
  (for [i 1 count]
    (set (. out i) 0))
  out)

(fn bytes-table-from-string [bytes]
  (local out {})
  (for [i 1 (string.len bytes)]
    (set (. out i) (string.byte bytes i)))
  out)

(fn bytes-string-from-table [bytes]
  (local parts [])
  (local size (length bytes))
  (local chunk-size 4096)
  (for [start 1 size chunk-size]
    (local finish (math.min size (+ start chunk-size -1)))
    (table.insert parts
                  (string.char (table.unpack bytes start finish))))
  (table.concat parts))

(fn tile-dir [data-dir layer]
  (assert (and (= (type data-dir) :string)
               (not (= data-dir "")))
          "RasterLayer requires non-empty data-dir")
  (assert layer.storage "RasterLayer requires layer.storage")
  (assert layer.storage.base_path "RasterLayer requires storage base_path")
  (fs.join-path data-dir layer.storage.base_path))

(fn tile-path [runtime tx ty]
  (fs.join-path runtime.base-dir (.. (tostring tx) "_" (tostring ty) ".png")))

(fn tile-key-from-entry [entry]
  (tile-key entry.tx entry.ty))

(fn scan-persisted-tiles [base-dir]
  (local out {})
  (when (fs.exists base-dir)
    (each [_ entry (ipairs (fs.list-dir base-dir))]
      (when (= entry.type "file")
        (local (tx-str ty-str)
               (string.match entry.name "^(-?%d+)_(-?%d+)%.png$"))
        (when (and tx-str ty-str)
          (local tx (tonumber tx-str))
          (local ty (tonumber ty-str))
          (set (. out (tile-key tx ty)) {:tx tx :ty ty})))))
  out)

(fn ensure-dir [path]
  (local (ok err) (pcall fs.create-dirs path))
  (when (not ok)
    (error (.. "RasterLayer failed to create " path ": " err))))

(fn remove-file-if-exists! [path]
  (when (fs.exists path)
    (local (ok err) (pcall fs.remove path))
    (when (not ok)
      (error (.. "RasterLayer failed to remove " path ": " err)))))

(fn pixel-index [runtime x y]
  (+ (* (+ (* y runtime.tile-size) x) channels) 1))

(fn world->pixel [value]
  (round-int value))

(fn normalize-bounds [start finish]
  (local left (math.min (world->pixel start.x) (world->pixel finish.x)))
  (local right (math.max (world->pixel start.x) (world->pixel finish.x)))
  (local bottom (math.min (world->pixel start.y) (world->pixel finish.y)))
  (local top (math.max (world->pixel start.y) (world->pixel finish.y)))
  {:left left
   :right right
   :bottom bottom
   :top top
   :width (+ (- right left) 1)
   :height (+ (- top bottom) 1)})

(fn ensure-tile-bytes-size [bytes runtime]
  (local expected (* runtime.tile-size runtime.tile-size channels))
  (assert (= (length bytes) expected)
          "RasterLayer tile byte length mismatch")
  bytes)

(fn load-tile-bytes [path runtime]
  (local png (ImageIO.read-png path))
  (assert (= png.width runtime.tile-size)
          (.. "RasterLayer tile width mismatch in " path))
  (assert (= png.height runtime.tile-size)
          (.. "RasterLayer tile height mismatch in " path))
  (assert (= png.channels channels)
          (.. "RasterLayer tile channel mismatch in " path))
  (ensure-tile-bytes-size
    (bytes-table-from-string (ImageIO.flip-vertical png.width png.height png.channels png.bytes))
    runtime))

(fn load-persisted-tile! [runtime tx ty]
  (local key (tile-key tx ty))
  (local existing (. runtime.tiles key))
  (if existing
      existing
      (if (. runtime.persisted-tiles key)
          (do
            (local path (tile-path runtime tx ty))
            (local loaded {:tx tx
                           :ty ty
                           :bytes (load-tile-bytes path runtime)
                           :dirty? false
                           :texture nil
                           :image-handle nil})
            (set (. runtime.tiles key) loaded)
            loaded)
          nil)))

(fn load-render-tile [runtime tx ty]
  (local key (tile-key tx ty))
  (or (. runtime.tiles key)
      (and (. runtime.persisted-tiles key)
           {:tx tx
            :ty ty
            :bytes (load-tile-bytes (tile-path runtime tx ty) runtime)
            :dirty? false})))

(fn get-pixel-rgba [runtime x y]
  (local tx (floor-div x runtime.tile-size))
  (local ty (floor-div y runtime.tile-size))
  (local key (tile-key tx ty))
  (local tile
    (or (. runtime.tiles key)
        (load-persisted-tile! runtime tx ty)))
  (if (not tile)
      [0 0 0 0]
      (do
        (local local-x (- x (* tx runtime.tile-size)))
        (local local-y (- y (* ty runtime.tile-size)))
        (if (or (< local-x 0)
                (< local-y 0)
                (>= local-x runtime.tile-size)
                (>= local-y runtime.tile-size))
            [0 0 0 0]
            (do
              (local idx (pixel-index runtime local-x local-y))
              [(. tile.bytes idx)
               (. tile.bytes (+ idx 1))
               (. tile.bytes (+ idx 2))
               (. tile.bytes (+ idx 3))])))))

(fn rgba= [left right]
  (and (= (. left 1) (. right 1))
       (= (. left 2) (. right 2))
       (= (. left 3) (. right 3))
       (= (. left 4) (. right 4))))

(fn tile-empty? [tile]
  (var opaque? false)
  (for [idx 4 (length tile.bytes) 4]
    (when (> (. tile.bytes idx) 0)
      (set opaque? true)
      (lua "break")))
  (not opaque?))

(fn ensure-tile! [runtime tx ty]
  (local key (tile-key tx ty))
  (local existing (. runtime.tiles key))
  (if existing
      existing
      (do
        (local path (tile-path runtime tx ty))
        (local persisted? (or (. runtime.persisted-tiles key)
                              (fs.exists path)))
        (local tile {:tx tx
                     :ty ty
                     :bytes (if persisted?
                                (load-tile-bytes path runtime)
                                (blank-bytes runtime.tile-size))
                     :dirty? (not persisted?)
                     :texture nil
                     :image-handle nil})
        (when persisted?
          (set (. runtime.persisted-tiles key) {:tx tx :ty ty}))
        (set (. runtime.tiles key) tile)
        tile)))

(fn set-pixel! [runtime x y rgba]
  (local tx (floor-div x runtime.tile-size))
  (local ty (floor-div y runtime.tile-size))
  (local tile (ensure-tile! runtime tx ty))
  (local local-x (- x (* tx runtime.tile-size)))
  (local local-y (- y (* ty runtime.tile-size)))
  (if (or (< local-x 0)
          (< local-y 0)
          (>= local-x runtime.tile-size)
          (>= local-y runtime.tile-size))
      nil
      (do
        (local idx (pixel-index runtime local-x local-y))
        (set (. tile.bytes idx) (. rgba 1))
        (set (. tile.bytes (+ idx 1)) (. rgba 2))
        (set (. tile.bytes (+ idx 2)) (. rgba 3))
        (set (. tile.bytes (+ idx 3)) (. rgba 4))
        (set tile.dirty? true)
        tile)))

(fn premultiply-rgba [rgba]
  (local alpha (/ (or (. rgba 4) 0) 255.0))
  [(round-int (* (or (. rgba 1) 0) alpha))
   (round-int (* (or (. rgba 2) 0) alpha))
   (round-int (* (or (. rgba 3) 0) alpha))
   (or (. rgba 4) 0)])

(fn blend-pixel! [runtime x y rgba]
  (local tx (floor-div x runtime.tile-size))
  (local ty (floor-div y runtime.tile-size))
  (local tile (ensure-tile! runtime tx ty))
  (local local-x (- x (* tx runtime.tile-size)))
  (local local-y (- y (* ty runtime.tile-size)))
  (if (or (< local-x 0)
          (< local-y 0)
          (>= local-x runtime.tile-size)
          (>= local-y runtime.tile-size))
      nil
      (do
        (local idx (pixel-index runtime local-x local-y))
        (local src-a (/ (. rgba 4) 255))
        (local dst-a (/ (. tile.bytes (+ idx 3)) 255))
        (local out-a (+ src-a (* dst-a (- 1 src-a))))
        (if (<= out-a 0)
            (do
              (set (. tile.bytes idx) 0)
              (set (. tile.bytes (+ idx 1)) 0)
              (set (. tile.bytes (+ idx 2)) 0)
              (set (. tile.bytes (+ idx 3)) 0))
            (do
              (set (. tile.bytes idx)
                   (round-int (+ (. rgba 1)
                                 (* (. tile.bytes idx) (- 1 src-a)))))
              (set (. tile.bytes (+ idx 1))
                   (round-int (+ (. rgba 2)
                                 (* (. tile.bytes (+ idx 1)) (- 1 src-a)))))
              (set (. tile.bytes (+ idx 2))
                   (round-int (+ (. rgba 3)
                                 (* (. tile.bytes (+ idx 2)) (- 1 src-a)))))
              (set (. tile.bytes (+ idx 3))
                   (round-int (* out-a 255)))))
        (set tile.dirty? true)
        tile)))

(fn clear-rect! [runtime bounds]
  (for [y bounds.bottom bounds.top]
    (for [x bounds.left bounds.right]
      (set-pixel! runtime x y [0 0 0 0]))))

(fn capture-fragment [runtime bounds]
  (local bytes {})
  (for [y bounds.bottom bounds.top]
    (for [x bounds.left bounds.right]
      (local rgba (get-pixel-rgba runtime x y))
      (table.insert bytes (. rgba 1))
      (table.insert bytes (. rgba 2))
      (table.insert bytes (. rgba 3))
      (table.insert bytes (. rgba 4))))
  {:origin {:x bounds.left
            :y bounds.bottom}
   :width bounds.width
   :height bounds.height
   :bytes bytes})

(fn blend-fragment-pixel! [runtime x y rgba]
  (if (= (. rgba 4) 0)
      nil
      (blend-pixel! runtime x y rgba)))

(fn apply-fragment! [runtime fragment dest-x dest-y]
  (var idx 1)
  (for [row 0 (- fragment.height 1)]
    (for [col 0 (- fragment.width 1)]
      (local rgba [(. fragment.bytes idx)
                   (. fragment.bytes (+ idx 1))
                   (. fragment.bytes (+ idx 2))
                   (. fragment.bytes (+ idx 3))])
      (blend-fragment-pixel! runtime (+ dest-x col) (+ dest-y row) rgba)
      (set idx (+ idx 4)))))

(fn rgba-from-style [color opacity pressure]
  (local alpha (* (or (. color 4) 1.0)
                  (or opacity 1.0)
                  (or pressure 1.0)))
  (premultiply-rgba
    [(round-int (* (clamp (or (. color 1) 0.0) 0.0 1.0) 255))
     (round-int (* (clamp (or (. color 2) 0.0) 0.0 1.0) 255))
     (round-int (* (clamp (or (. color 3) 0.0) 0.0 1.0) 255))
     (round-int (* (clamp alpha 0.0 1.0) 255))]))

(fn erase-rgba []
  [0 0 0 0])

(fn stamp-disk! [runtime cx cy radius rgba erase?]
  (local min-x (math.floor (- cx radius)))
  (local max-x (math.ceil (+ cx radius)))
  (local min-y (math.floor (- cy radius)))
  (local max-y (math.ceil (+ cy radius)))
  (local r2 (* radius radius))
  (for [y min-y max-y]
    (for [x min-x max-x]
      (local dx (- x cx))
      (local dy (- y cy))
      (when (<= (+ (* dx dx) (* dy dy)) r2)
        (if erase?
            (set-pixel! runtime x y rgba)
            (blend-pixel! runtime x y rgba))))))

(fn stroke-samples! [runtime samples radius style erase?]
  (local count (length samples))
  (when (> count 0)
    (for [idx 1 count]
      (local sample (. samples idx))
      (local previous (and (> idx 1) (. samples (- idx 1))))
      (local pressure
        (if (and style.pressure_opacity (not erase?))
            (or sample.pressure 1.0)
            1.0))
      (local radius-pressure
        (if style.pressure_size
            (or sample.pressure 1.0)
            1.0))
      (local sample-radius (math.max 0.75 (* radius radius-pressure)))
      (local rgba
        (if erase?
            (erase-rgba)
            (rgba-from-style style.stroke_color style.opacity pressure)))
      (if previous
          (do
            (local dx (- sample.point.x previous.point.x))
            (local dy (- sample.point.y previous.point.y))
            (local distance (math.sqrt (+ (* dx dx) (* dy dy))))
            (local spacing (math.max 0.5 (* sample-radius 0.35)))
            (local steps (math.max 1 (math.ceil (/ distance spacing))))
            (for [step 0 steps]
              (local t (/ step steps))
              (stamp-disk! runtime
                           (+ previous.point.x (* dx t))
                           (+ previous.point.y (* dy t))
                           sample-radius
                           rgba
                           erase?)))
          (stamp-disk! runtime sample.point.x sample.point.y sample-radius rgba erase?)))))

(fn normalized-rgba [color opacity]
  (rgba-from-style color opacity 1.0))

(fn stroke-rect-outline! [runtime left bottom right top thickness rgba erase?]
  (for [offset 0 (math.max 0 (- (round-int thickness) 1))]
    (for [x left right]
      (if erase?
          (do
            (set-pixel! runtime x (+ bottom offset) rgba)
            (set-pixel! runtime x (- top offset) rgba))
          (do
            (blend-pixel! runtime x (+ bottom offset) rgba)
            (blend-pixel! runtime x (- top offset) rgba))))
    (for [y bottom top]
      (if erase?
          (do
            (set-pixel! runtime (+ left offset) y rgba)
            (set-pixel! runtime (- right offset) y rgba))
          (do
            (blend-pixel! runtime (+ left offset) y rgba)
            (blend-pixel! runtime (- right offset) y rgba))))))

(fn stamp-rectangle! [runtime start finish style]
  (local left (math.min (world->pixel start.x) (world->pixel finish.x)))
  (local right (math.max (world->pixel start.x) (world->pixel finish.x)))
  (local bottom (math.min (world->pixel start.y) (world->pixel finish.y)))
  (local top (math.max (world->pixel start.y) (world->pixel finish.y)))
  (when style.fill_enabled
    (local fill-rgba (normalized-rgba style.fill_color style.opacity))
    (for [y bottom top]
      (for [x left right]
        (blend-pixel! runtime x y fill-rgba))))
  (stroke-rect-outline! runtime
                        left
                        bottom
                        right
                        top
                        (or style.thickness 1.0)
                        (normalized-rgba style.stroke_color style.opacity)
                        false))

(fn stamp-line! [runtime start finish style]
  (local samples [{:point start :pressure 1.0}
                  {:point finish :pressure 1.0}])
  (stroke-samples! runtime
                   samples
                   (* 0.5 (math.max 1.0 (or style.thickness 1.0)))
                   style
                   false))

(fn stamp-ellipse! [runtime start finish style]
  (local left (math.min (world->pixel start.x) (world->pixel finish.x)))
  (local right (math.max (world->pixel start.x) (world->pixel finish.x)))
  (local bottom (math.min (world->pixel start.y) (world->pixel finish.y)))
  (local top (math.max (world->pixel start.y) (world->pixel finish.y)))
  (local cx (* (+ left right) 0.5))
  (local cy (* (+ bottom top) 0.5))
  (local rx (math.max 0.5 (* (- right left) 0.5)))
  (local ry (math.max 0.5 (* (- top bottom) 0.5)))
  (local fill-rgba (normalized-rgba style.fill_color style.opacity))
  (local stroke-rgba (normalized-rgba style.stroke_color style.opacity))
  (local edge-thickness (math.max 1.0 (or style.thickness 1.0)))
  (for [y bottom top]
    (for [x left right]
      (local nx (/ (- x cx) rx))
      (local ny (/ (- y cy) ry))
      (local d (+ (* nx nx) (* ny ny)))
      (when (and style.fill_enabled (<= d 1.0))
        (blend-pixel! runtime x y fill-rgba))
      (when (and (<= (math.abs (- 1.0 d))
                     (/ edge-thickness (math.max rx ry)))
                 (> edge-thickness 0))
        (blend-pixel! runtime x y stroke-rgba)))))

(fn sorted-tile-keys [tiles]
  (local keys [])
  (each [key _tile (pairs tiles)]
    (table.insert keys key))
  (table.sort keys)
  keys)

(fn sorted-entry-keys [entries]
  (local keys [])
  (each [key _value (pairs entries)]
    (table.insert keys key))
  (table.sort keys)
  keys)

(fn all-tile-entries [runtime]
  (local out {})
  (each [key entry (pairs runtime.persisted-tiles)]
    (set (. out key) entry))
  (each [key tile (pairs runtime.tiles)]
    (set (. out key) {:tx tile.tx :ty tile.ty}))
  out)

(fn capture-bytes [runtime keys]
  (local out {})
  (each [_ key (ipairs keys)]
    (local coords (parse-tile-key key))
    (local tile
      (or (. runtime.tiles key)
          (and (. runtime.persisted-tiles key)
               (load-persisted-tile! runtime coords.tx coords.ty))))
    (table.insert out {:tx coords.tx
                       :ty coords.ty
                       :bytes (and tile (bytes-string-from-table tile.bytes))}))
  out)

(fn prune-empty-tiles! [runtime keys]
  (each [_ key (ipairs keys)]
    (local tile (. runtime.tiles key))
    (when (and tile (tile-empty? tile))
      (set (. runtime.tiles key) nil)
      (set (. runtime.persisted-tiles key) nil))))

(fn apply-captured-bytes! [runtime captured]
  (each [_ entry (ipairs (or captured []))]
    (local key (tile-key entry.tx entry.ty))
    (if (= entry.bytes nil)
      (do
        (set (. runtime.tiles key) nil)
        (set (. runtime.persisted-tiles key) nil))
        (do
          (local tile (ensure-tile! runtime entry.tx entry.ty))
          (set tile.bytes (bytes-table-from-string entry.bytes))
          (set tile.dirty? true)
          (set (. runtime.persisted-tiles key) {:tx entry.tx :ty entry.ty})))))

(fn save-tile! [runtime tile]
  (ensure-dir runtime.base-dir)
  (local bytes (bytes-string-from-table tile.bytes))
  (ImageIO.write-png (tile-path runtime tile.tx tile.ty)
                     runtime.tile-size
                     runtime.tile-size
                     channels
                     bytes
                     true)
  (set tile.dirty? false)
  (set (. runtime.persisted-tiles (tile-key tile.tx tile.ty))
       {:tx tile.tx :ty tile.ty}))

(fn save! [runtime]
  (ensure-dir runtime.base-dir)
  (each [_ key (ipairs (sorted-tile-keys runtime.tiles))]
    (local tile (. runtime.tiles key))
    (when tile
      (if (tile-empty? tile)
          (do
            (remove-file-if-exists! (tile-path runtime tile.tx tile.ty))
            (set (. runtime.tiles key) nil)
            (set (. runtime.persisted-tiles key) nil))
          (save-tile! runtime tile))))
  (each [_ entry (ipairs (fs.list-dir runtime.base-dir))]
    (when (= entry.type "file")
      (local (tx-str ty-str)
             (string.match entry.name "^(-?%d+)_(-?%d+)%.png$"))
      (when (and tx-str ty-str)
        (local key (tile-key (tonumber tx-str) (tonumber ty-str)))
        (when (= (. runtime.persisted-tiles key) nil)
          (remove-file-if-exists! (fs.join-path runtime.base-dir entry.name))
          (set (. runtime.persisted-tiles key) nil)))))
  true)

(fn collect-sample-tile-keys [runtime samples radius]
  (local keys {})
  (each [_ sample (ipairs (or samples []))]
    (local min-tx (floor-div (- sample.point.x radius) runtime.tile-size))
    (local max-tx (floor-div (+ sample.point.x radius) runtime.tile-size))
    (local min-ty (floor-div (- sample.point.y radius) runtime.tile-size))
    (local max-ty (floor-div (+ sample.point.y radius) runtime.tile-size))
    (for [ty min-ty max-ty]
      (for [tx min-tx max-tx]
        (set (. keys (tile-key tx ty)) {:tx tx :ty ty}))))
  keys)

(fn collect-shape-tile-keys [runtime start finish thickness]
  (local min-tx (floor-div (- (math.min start.x finish.x) thickness) runtime.tile-size))
  (local max-tx (floor-div (+ (math.max start.x finish.x) thickness) runtime.tile-size))
  (local min-ty (floor-div (- (math.min start.y finish.y) thickness) runtime.tile-size))
  (local max-ty (floor-div (+ (math.max start.y finish.y) thickness) runtime.tile-size))
  (local keys {})
  (for [ty min-ty max-ty]
    (for [tx min-tx max-tx]
      (set (. keys (tile-key tx ty)) {:tx tx :ty ty})))
  keys)

(fn collect-bounds-tile-keys [runtime bounds]
  (local min-tx (floor-div bounds.left runtime.tile-size))
  (local max-tx (floor-div bounds.right runtime.tile-size))
  (local min-ty (floor-div bounds.bottom runtime.tile-size))
  (local max-ty (floor-div bounds.top runtime.tile-size))
  (local keys {})
  (for [ty min-ty max-ty]
    (for [tx min-tx max-tx]
      (set (. keys (tile-key tx ty)) {:tx tx :ty ty})))
  keys)

(fn merge-key-maps [left right]
  (local out {})
  (each [key value (pairs left)]
    (set (. out key) value))
  (each [key value (pairs right)]
    (set (. out key) value))
  out)

(fn component-bounds [runtime min-tx max-tx min-ty max-ty]
  {:left (* min-tx runtime.tile-size)
   :right (+ (* (+ max-tx 1) runtime.tile-size) -1)
   :bottom (* min-ty runtime.tile-size)
   :top (+ (* (+ max-ty 1) runtime.tile-size) -1)})

(fn point-in-bounds? [x y bounds]
  (and bounds
       (>= x bounds.left)
       (<= x bounds.right)
       (>= y bounds.bottom)
       (<= y bounds.top)))

(fn bounds-area [bounds]
  (* (+ (- bounds.right bounds.left) 1)
     (+ (- bounds.top bounds.bottom) 1)))

(fn tile-component-bounds [runtime seed-x seed-y]
  (local tile-entries (all-tile-entries runtime))
  (local visited {})
  (local components [])
  (each [key entry (pairs tile-entries)]
    (when (not (. visited key))
      (local queue [entry])
      (var head 1)
      (var min-tx entry.tx)
      (var max-tx entry.tx)
      (var min-ty entry.ty)
      (var max-ty entry.ty)
      (set (. visited key) true)
      (while (<= head (length queue))
        (local current (. queue head))
        (set head (+ head 1))
        (set min-tx (math.min min-tx current.tx))
        (set max-tx (math.max max-tx current.tx))
        (set min-ty (math.min min-ty current.ty))
        (set max-ty (math.max max-ty current.ty))
        (each [_ offset (ipairs [[1 0] [-1 0] [0 1] [0 -1]])]
          (local neighbor-key
            (tile-key (+ current.tx (. offset 1))
                      (+ current.ty (. offset 2))))
          (local neighbor (. tile-entries neighbor-key))
          (when (and neighbor (not (. visited neighbor-key)))
            (set (. visited neighbor-key) true)
            (table.insert queue neighbor))))
      (table.insert components
                    {:bounds (component-bounds runtime min-tx max-tx min-ty max-ty)
                     :min-tx min-tx
                     :max-tx max-tx
                     :min-ty min-ty
                     :max-ty max-ty})))
  (table.sort components
              (fn [left right]
                (local left-area (bounds-area left.bounds))
                (local right-area (bounds-area right.bounds))
                (if (not (= left-area right-area))
                    (< left-area right-area)
                    (not (= left.min-ty right.min-ty))
                    (< left.min-ty right.min-ty)
                    (not (= left.min-tx right.min-tx))
                    (< left.min-tx right.min-tx)
                    (not (= left.max-ty right.max-ty))
                    (< left.max-ty right.max-ty)
                    (< left.max-tx right.max-tx))))
  (var containing nil)
  (each [_ component (ipairs components)]
    (when (and (not containing)
               (point-in-bounds? seed-x seed-y component.bounds))
      (set containing component.bounds)))
  containing)

(fn rgba-distance [left right]
  (math.max (math.abs (- (. left 1) (. right 1)))
            (math.abs (- (. left 2) (. right 2)))
            (math.abs (- (. left 3) (. right 3)))
            (math.abs (- (. left 4) (. right 4)))))

(fn within-rgba-tolerance? [left right tolerance]
  (<= (rgba-distance left right) tolerance))

(fn capture-existing-bytes [runtime key-map]
  (local before [])
  (each [_ entry (pairs key-map)]
    (local tile
      (or (. runtime.tiles (tile-key-from-entry entry))
          (and (. runtime.persisted-tiles (tile-key-from-entry entry))
               (load-persisted-tile! runtime entry.tx entry.ty))))
    (table.insert before {:tx entry.tx
                          :ty entry.ty
                          :bytes (and tile (bytes-string-from-table tile.bytes))}))
  (table.sort before
              (fn [left right]
                (if (= left.ty right.ty)
                    (< left.tx right.tx)
                    (< left.ty right.ty))))
  before)

(fn stroke! [runtime tool samples style]
  (local first-sample (. samples 1))
  (local last-sample (. samples (length samples)))
  (assert first-sample "RasterLayerRuntime.stroke! requires samples")
  (assert last-sample "RasterLayerRuntime.stroke! requires samples")
  (local key-map
    (if (or (= tool "rectangle") (= tool "ellipse") (= tool "line"))
        (collect-shape-tile-keys runtime first-sample.point last-sample.point (or style.thickness 1.0))
        (collect-sample-tile-keys runtime samples (* 0.5 (math.max 1.0 (or style.thickness 1.0))))))
  (local before (capture-existing-bytes runtime key-map))
  (if (= tool "rectangle")
      (stamp-rectangle! runtime first-sample.point last-sample.point style)
      (= tool "ellipse")
      (stamp-ellipse! runtime first-sample.point last-sample.point style)
      (= tool "line")
      (stamp-line! runtime first-sample.point last-sample.point style)
      (stroke-samples! runtime
                       samples
                       (* 0.5 (math.max 1.0 (or style.thickness 1.0)))
                       style
                       (= tool "eraser")))
  (prune-empty-tiles! runtime (sorted-entry-keys key-map))
  {:before before
   :after (capture-bytes runtime
                         (icollect [_ entry (ipairs before)]
                                   (tile-key entry.tx entry.ty)))
   :changed? true})

(fn fill! [runtime point style opts]
  (local options (or opts {}))
  (local seed-x (world->pixel point.x))
  (local seed-y (world->pixel point.y))
  (local seed-rgba (get-pixel-rgba runtime seed-x seed-y))
  (local extents (tile-component-bounds runtime seed-x seed-y))
  (local fill-rgba (normalized-rgba (or style.fill_color style.stroke_color) style.opacity))
  (local tolerance (or options.tolerance 24))
  (if (or (not extents)
          (rgba= seed-rgba fill-rgba)
          (< seed-x extents.left)
          (> seed-x extents.right)
          (< seed-y extents.bottom)
          (> seed-y extents.top))
      {:before []
       :after []
       :changed? false}
      (do
        (local queue-x [seed-x])
        (local queue-y [seed-y])
        (var head 1)
        (local visited {})
        (local changed-tiles {})
        (local fill-points [])
        (while (<= head (length queue-x))
          (local x (. queue-x head))
          (local y (. queue-y head))
          (set head (+ head 1))
          (local visit-key (.. (tostring x) ":" (tostring y)))
          (when (not (. visited visit-key))
            (set (. visited visit-key) true)
            (when (and (>= x extents.left)
                       (<= x extents.right)
                       (>= y extents.bottom)
                       (<= y extents.top)
                       (within-rgba-tolerance? (get-pixel-rgba runtime x y) seed-rgba tolerance))
              (table.insert fill-points {:x x :y y})
              (local tx (floor-div x runtime.tile-size))
              (local ty (floor-div y runtime.tile-size))
              (set (. changed-tiles (tile-key tx ty)) {:tx tx :ty ty})
              (table.insert queue-x (+ x 1))
              (table.insert queue-y y)
              (table.insert queue-x (- x 1))
              (table.insert queue-y y)
              (table.insert queue-x x)
              (table.insert queue-y (+ y 1))
              (table.insert queue-x x)
              (table.insert queue-y (- y 1)))))
        (local before (capture-existing-bytes runtime changed-tiles))
        (each [_ entry (ipairs fill-points)]
          (set-pixel! runtime entry.x entry.y fill-rgba))
        (prune-empty-tiles! runtime (sorted-entry-keys changed-tiles))
        {:before before
         :after (capture-bytes runtime
                               (icollect [_ entry (ipairs before)]
                                         (tile-key entry.tx entry.ty)))
         :changed? true})))

(fn move-selection! [runtime selection dx dy]
  (local source-bounds selection.bounds)
  (local dest-bounds {:left (+ source-bounds.left dx)
                      :right (+ source-bounds.right dx)
                      :bottom (+ source-bounds.bottom dy)
                      :top (+ source-bounds.top dy)})
  (set dest-bounds.width source-bounds.width)
  (set dest-bounds.height source-bounds.height)
  (local key-map
    (merge-key-maps (collect-bounds-tile-keys runtime source-bounds)
                    (collect-bounds-tile-keys runtime dest-bounds)))
  (local before (capture-existing-bytes runtime key-map))
  (clear-rect! runtime source-bounds)
  (apply-fragment! runtime selection.fragment dest-bounds.left dest-bounds.bottom)
  (prune-empty-tiles! runtime (sorted-entry-keys key-map))
  {:before before
   :after (capture-bytes runtime
                         (icollect [_ entry (ipairs before)]
                                   (tile-key entry.tx entry.ty)))
   :changed? true
   :bounds dest-bounds})

(fn clear-selection! [runtime selection]
  (local bounds selection.bounds)
  (local before (capture-existing-bytes runtime (collect-bounds-tile-keys runtime bounds)))
  (clear-rect! runtime bounds)
  (prune-empty-tiles! runtime
                      (icollect [_ entry (ipairs before)]
                                (tile-key entry.tx entry.ty)))
  {:before before
   :after (capture-bytes runtime
                         (icollect [_ entry (ipairs before)]
                                   (tile-key entry.tx entry.ty)))
   :changed? true
   :bounds bounds})

(fn tile-records [runtime]
  (capture-bytes runtime
                 (sorted-entry-keys (all-tile-entries runtime))))

(fn visible-tile-entries [runtime bounds]
  (local out [])
  (local source (all-tile-entries runtime))
  (local min-tx (and bounds (floor-div bounds.left runtime.tile-size)))
  (local max-tx (and bounds (floor-div bounds.right runtime.tile-size)))
  (local min-ty (and bounds (floor-div bounds.bottom runtime.tile-size)))
  (local max-ty (and bounds (floor-div bounds.top runtime.tile-size)))
  (each [_ key (ipairs (sorted-entry-keys source))]
    (local entry (. source key))
    (when (or (not bounds)
              (and (>= entry.tx min-tx)
                   (<= entry.tx max-tx)
                   (>= entry.ty min-ty)
                   (<= entry.ty max-ty)))
      (table.insert out entry)))
  out)

(fn RasterLayerRuntime [opts]
  (local options (or opts {}))
  (local layer (assert options.layer "RasterLayerRuntime requires :layer"))
  (local data-dir options.data_dir)
  (assert (and (= (type data-dir) :string)
               (not (= data-dir "")))
          "RasterLayerRuntime requires non-empty :data_dir")
  (local tile-size (or (and layer.storage layer.storage.tile_size) default-tile-size))
  (local runtime {:layer-id layer.id
                  :tile-size tile-size
                  :tiles {}
                  :persisted-tiles {}
                  :base-dir (tile-dir data-dir layer)})

  (set runtime.persisted-tiles (scan-persisted-tiles runtime.base-dir))

  {:ensure-tile! (fn [_self tx ty] (ensure-tile! runtime tx ty))
   :apply-captured-bytes! (fn [_self captured] (apply-captured-bytes! runtime captured))
   :stroke! (fn [_self tool samples style] (stroke! runtime tool samples style))
   :fill! (fn [_self point style opts] (fill! runtime point style opts))
   :render-tile (fn [_self tx ty] (load-render-tile runtime tx ty))
   :normalize-bounds (fn [_self start finish] (normalize-bounds start finish))
   :get-pixel-rgba (fn [_self x y] (get-pixel-rgba runtime x y))
   :capture-fragment (fn [_self bounds] (capture-fragment runtime bounds))
   :move-selection! (fn [_self selection dx dy] (move-selection! runtime selection dx dy))
   :clear-selection! (fn [_self selection] (clear-selection! runtime selection))
   :tile-records (fn [_self] (tile-records runtime))
   :visible-tile-entries (fn [_self bounds] (visible-tile-entries runtime bounds))
   :save! (fn [_self] (save! runtime))
   :runtime runtime})

{:RasterLayerRuntime RasterLayerRuntime
 :normalize-bounds normalize-bounds
 :rgba-from-style rgba-from-style
 :bytes-string-from-table bytes-string-from-table
 :bytes-table-from-string bytes-table-from-string}

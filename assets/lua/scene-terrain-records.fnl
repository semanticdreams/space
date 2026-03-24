(local glm (require :glm))
(local Uuid (require :uuid))
(local MathUtils (require :math-utils))
(local FlatTerrain (require :flat-terrain))
(local HeightfieldTerrain (require :heightfield-terrain))
(local PerlinTerrain (require :perlin-terrain))

(local vec3->array (. MathUtils :vec3->array))
(local quat->array (. MathUtils :quat->array))
(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn positive-integer? [value]
  (and (finite-number? value)
       (= value (math.floor value))
       (> value 0)))

(fn integer? [value]
  (and (finite-number? value)
       (= value (math.floor value))))

(fn resolve-vec3 [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    (= (type value) :number) (glm.vec3 value value value)
    (= (type value) :table)
      (do
        (local x (or (. value 1) value.x (. value "x")))
        (local y (or (. value 2) value.y (. value "y")))
        (local z (or (. value 3) value.z (. value "z")))
        (if (and (finite-number? x) (finite-number? y) (finite-number? z))
            (glm.vec3 x y z)
            fallback))
    fallback))

(fn resolve-vec4 [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    (= (type value) :table)
      (do
        (local x (or (. value 1) value.x (. value "x")))
        (local y (or (. value 2) value.y (. value "y")))
        (local z (or (. value 3) value.z (. value "z")))
        (local w (or (. value 4) value.w (. value "w") 1.0))
        (if (and (finite-number? x) (finite-number? y) (finite-number? z) (finite-number? w))
            (glm.vec4 x y z w)
            fallback))
    fallback))

(fn resolve-quat [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    (= (type value) :table)
      (do
        (local w (or (. value 1) value.w (. value "w")))
        (local x (or (. value 2) value.x (. value "x")))
        (local y (or (. value 3) value.y (. value "y")))
        (local z (or (. value 4) value.z (. value "z")))
        (if (and (finite-number? w) (finite-number? x) (finite-number? y) (finite-number? z))
            (glm.quat w x y z)
            fallback))
    fallback))

(local default-flat-options
  {:width 50
   :length 50
   :scale [20 1 20]
   :position [-500 -100 -500]
   :rotation [1 0 0 0]
   :opacity 1.0
   :physics-thickness 2.0})

(local default-perlin-options
  {:width 50
   :length 50
   :seed 1337
   :scale [20 1 20]
   :position [500 -100 -500]
   :rotation [1 0 0 0]
   :opacity 1.0
   :physics true
   :n1div 30
   :n2div 4
   :n3div 1
   :n1scale 20
   :n2scale 2
   :n3scale 1
   :zroot 2
   :zpower 2.5})

(local default-heightfield-options
  {:position [-160 -100 -160]
   :rotation [1 0 0 0]
   :opacity 1.0
   :physics true
   :sample-spacing [20 20]
   :chunk-samples [17 17]
   :default-height 0.0})

(fn normalize-chunk-samples [value]
  (local source (or value [17 17]))
  (local width (or (. source 1) source.x 17))
  (local depth (or (. source 2) source.y source.z 17))
  (assert (positive-integer? width) "Heightfield chunk sample width must be a positive integer")
  (assert (positive-integer? depth) "Heightfield chunk sample length must be a positive integer")
  (assert (>= width 2) "Heightfield chunk sample width must be at least 2")
  (assert (>= depth 2) "Heightfield chunk sample length must be at least 2")
  [(math.floor width) (math.floor depth)])

(fn normalize-sample-spacing [value]
  (local source (or value [20 20]))
  (local width (or (. source 1) source.x 20))
  (local depth (or (. source 2) source.y source.z 20))
  (assert (and (finite-number? width) (> width 0)) "Heightfield sample spacing X must be a positive number")
  (assert (and (finite-number? depth) (> depth 0)) "Heightfield sample spacing Z must be a positive number")
  [width depth])

(fn default-heightfield-heights [size default-height]
  (local width (. size 1))
  (local depth (. size 2))
  (local heights [])
  (for [_ 1 (* width depth)]
    (table.insert heights default-height))
  heights)

(fn normalize-heightfield-chunks [chunks options]
  (local chunk-samples (normalize-chunk-samples options.chunk-samples))
  (local default-height
    (if (finite-number? options.default-height)
        options.default-height
        0.0))
  (if (or (= chunks nil) (= (length chunks) 0))
      [{:coord [0 0]
        :size chunk-samples
        :heights (default-heightfield-heights chunk-samples default-height)}]
      (do
        (local out [])
        (local seen {})
        (each [_ chunk (ipairs chunks)]
          (local raw (or chunk {}))
          (local raw-coord (or raw.coord [0 0]))
          (local chunk-x (or (. raw-coord 1) raw-coord.x 0))
          (local chunk-z (or (. raw-coord 2) raw-coord.y raw-coord.z 0))
          (assert (integer? chunk-x)
                  "Heightfield chunk X coordinate must be an integer")
          (assert (integer? chunk-z)
                  "Heightfield chunk Z coordinate must be an integer")
          (local size
            (if raw.size
                (normalize-chunk-samples raw.size)
                chunk-samples))
          (assert (= (. size 1) (. chunk-samples 1))
                  "Heightfield chunk size must match terrain chunk-samples width")
          (assert (= (. size 2) (. chunk-samples 2))
                  "Heightfield chunk size must match terrain chunk-samples length")
          (local coord-key (.. chunk-x ":" chunk-z))
          (assert (not (. seen coord-key))
                  (.. "Duplicate heightfield chunk coordinate " coord-key))
          (set (. seen coord-key) true)
          (var heights [])
          (local expected-count (* (. size 1) (. size 2)))
          (if (= raw.heights nil)
              (set heights (default-heightfield-heights size default-height))
              (do
                (assert (= (length raw.heights) expected-count)
                        "Heightfield chunk heights length must match chunk sample count")
                (each [_ value (ipairs raw.heights)]
                  (assert (finite-number? value) "Heightfield chunk heights must be finite numbers")
                  (table.insert heights value))))
          (table.insert out {:coord [chunk-x chunk-z]
                             :size size
                             :heights heights}))
        out)))

(local terrain-kind-spec-list
  [{:kind "heightfield-terrain"
    :label "Heightfield Terrain"
    :default-options default-heightfield-options}])

(local terrain-kind-specs {})

(each [_ spec (ipairs terrain-kind-spec-list)]
  (set (. terrain-kind-specs spec.kind) spec))

(fn terrain-kind-spec [kind]
  (. terrain-kind-specs kind))

(fn supported-kinds []
  (icollect [_ spec (ipairs terrain-kind-spec-list)] spec.kind))

(fn kind-default-options [kind]
  (local spec (terrain-kind-spec kind))
  (if spec
      spec.default-options
      {}))

(fn supported-kind? [kind]
  (or (= kind "flat-terrain")
      (= kind "heightfield-terrain")
      (= kind "perlin-terrain")))

(fn normalize-record [record]
  (local raw (or record {}))
  (local kind raw.kind)
  (assert (= (type kind) :string) "Terrain record kind must be a string")
  (assert (> (string.len kind) 0) "Terrain record kind must not be empty")
  (local id
    (if (and raw.id (= (type raw.id) :string) (> (string.len raw.id) 0))
        raw.id
        (Uuid.v4)))
  (local defaults (kind-default-options kind))
  (local options (clone-table defaults))
  (each [k v (pairs (or raw.options {}))]
    (set (. options k) (clone-table v)))
  (when (= kind "heightfield-terrain")
    (set options.chunk-samples (normalize-chunk-samples options.chunk-samples))
    (set options.sample-spacing (normalize-sample-spacing options.sample-spacing))
    (when (not (finite-number? options.default-height))
      (set options.default-height 0.0)))
  (local normalized {:id id
                     :name (if (and raw.name (= (type raw.name) :string) (> (string.len raw.name) 0))
                               raw.name
                               nil)
                     :kind kind
                     :options options})
  (when (= kind "heightfield-terrain")
    (set normalized.chunks (normalize-heightfield-chunks raw.chunks options)))
  normalized)

(fn normalize-records [records]
  (var out [])
  (each [_ record (ipairs (or records []))]
    (table.insert out (normalize-record record)))
  out)

(fn default-record-for-kind [kind]
  (assert (terrain-kind-spec kind)
          (.. "Unsupported terrain kind for record defaults: " (tostring kind)))
  (normalize-record {:kind kind}))

(fn default-records []
  [(default-record-for-kind "heightfield-terrain")])

(fn supported-record? [record]
  (local normalized (normalize-record record))
  (supported-kind? normalized.kind))

(fn builder-for-record [record]
  (local normalized (normalize-record record))
  (local options (or normalized.options {}))
  (local position (resolve-vec3 options.position (glm.vec3 0 0 0)))
  (local rotation (resolve-quat options.rotation (glm.quat 1 0 0 0)))
  (if (= normalized.kind "flat-terrain")
      {:record normalized
       :position position
       :rotation rotation
       :builder
       (FlatTerrain {:width options.width
                     :length options.length
                     :scale (resolve-vec3 options.scale (glm.vec3 20 1 20))
                     :position position
                     :rotation rotation
                     :opacity options.opacity
                     :physics-thickness options.physics-thickness})}
      (= normalized.kind "heightfield-terrain")
      {:record normalized
       :position position
       :rotation rotation
       :builder
       (HeightfieldTerrain {:position position
                            :rotation rotation
                            :opacity options.opacity
                            :physics options.physics
                            :sample-spacing options.sample-spacing
                            :chunks normalized.chunks})}
      (= normalized.kind "perlin-terrain")
      {:record normalized
       :position position
       :rotation rotation
       :builder
       (PerlinTerrain {:width options.width
                       :length options.length
                       :seed options.seed
                       :scale (resolve-vec3 options.scale (glm.vec3 20 1 20))
                       :position position
                       :rotation rotation
                       :opacity options.opacity
                       :physics options.physics
                       :n1div options.n1div
                       :n2div options.n2div
                       :n3div options.n3div
                       :n1scale options.n1scale
                       :n2scale options.n2scale
                       :n3scale options.n3scale
                       :zroot options.zroot
                       :zpower options.zpower})}
      (error (.. "Unsupported terrain kind for build: " normalized.kind))))

(fn merge-preserved-records [existing-records captured-records]
  (local existing (normalize-records existing-records))
  (local captured (normalize-records captured-records))
  (local captured-by-id {})
  (local consumed {})
  (each [_ record (ipairs captured)]
    (set (. captured-by-id record.id) record))
  (var merged [])
  (each [_ record (ipairs existing)]
    (if (supported-kind? record.kind)
        (do
          (local updated (. captured-by-id record.id))
          (when updated
            (table.insert merged updated)
            (set (. consumed record.id) true)))
        (table.insert merged record)))
  (each [_ record (ipairs captured)]
    (when (not (. consumed record.id))
      (table.insert merged record)))
  merged)

(fn capture-record [record layout]
  (local normalized (normalize-record record))
  (local captured (clone-table normalized))
  (local options (clone-table (or captured.options {})))
  (when (and layout layout.position)
    (set options.position (vec3->array layout.position)))
  (when (and layout layout.rotation)
    (set options.rotation (quat->array layout.rotation)))
  (set captured.options options)
  captured)

{:clone-table clone-table
 :normalize-record normalize-record
 :normalize-records normalize-records
 :supported-kinds supported-kinds
 :terrain-kind-spec terrain-kind-spec
 :default-record-for-kind default-record-for-kind
 :default-records default-records
 :supported-kind? supported-kind?
 :supported-record? supported-record?
 :builder-for-record builder-for-record
 :merge-preserved-records merge-preserved-records
 :capture-record capture-record
 :array->vec3 array->vec3
 :array->quat array->quat}

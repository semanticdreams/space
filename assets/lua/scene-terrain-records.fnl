(local glm (require :glm))
(local Uuid (require :uuid))
(local MathUtils (require :math-utils))
(local FlatTerrain (require :flat-terrain))
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

(local terrain-kind-spec-list
  [{:kind "flat-terrain"
    :label "Flat Terrain"
    :default-options default-flat-options}
   {:kind "perlin-terrain"
    :label "Perlin Terrain"
    :default-options default-perlin-options}])

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
  {:id id
   :kind kind
   :options options})

(fn normalize-records [records]
  (var out [])
  (each [_ record (ipairs (or records []))]
    (table.insert out (normalize-record record)))
  out)

(fn default-flat-record []
  (normalize-record {:kind "flat-terrain"}))

(fn default-perlin-record []
  (normalize-record {:kind "perlin-terrain"}))

(fn default-record-for-kind [kind]
  (assert (terrain-kind-spec kind)
          (.. "Unsupported terrain kind for record defaults: " (tostring kind)))
  (normalize-record {:kind kind}))

(fn default-records []
  [(default-flat-record)])

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
 :default-flat-record default-flat-record
 :default-perlin-record default-perlin-record
 :default-record-for-kind default-record-for-kind
 :default-records default-records
 :builder-for-record builder-for-record
 :capture-record capture-record
 :array->vec3 array->vec3
 :array->quat array->quat}

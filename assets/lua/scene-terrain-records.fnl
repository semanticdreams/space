(local glm (require :glm))
(local Uuid (require :uuid))
(local MathUtils (require :math-utils))
(local FlatTerrain (require :flat-terrain))

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

(fn kind-default-options [kind]
  (if (= kind "flat-terrain")
      default-flat-options
      {}))

(fn supported-kind? [kind]
  (= kind "flat-terrain"))

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

(fn default-records []
  [(default-flat-record)])

(fn supported-record? [record]
  (local normalized (normalize-record record))
  (supported-kind? normalized.kind))

(fn builder-for-record [record]
  (local normalized (normalize-record record))
  (local options (or normalized.options {}))
  (local position (resolve-vec3 options.position (glm.vec3 0 0 0)))
  (local rotation (resolve-quat options.rotation (glm.quat 1 0 0 0)))
  (if (supported-kind? normalized.kind)
      (do
        (local dark-color (resolve-vec4 (and options.colors options.colors.dark) nil))
        (local light-color (resolve-vec4 (and options.colors options.colors.light) nil))
        (local colors {:dark dark-color
                       :light light-color})
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
                       :physics-thickness options.physics-thickness
                       :colors colors})})
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
 :default-flat-record default-flat-record
 :default-records default-records
 :supported-kind? supported-kind?
 :supported-record? supported-record?
 :builder-for-record builder-for-record
 :merge-preserved-records merge-preserved-records
 :capture-record capture-record
 :array->vec3 array->vec3
 :array->quat array->quat}

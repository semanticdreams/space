(local glm (require :glm))
(local bt (require :bt))
(local HeightfieldTerrainSpace (require :heightfield-terrain-space))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldTerrainGrid (require :heightfield-terrain-grid))

(fn vec3-changed? [a b eps]
  (local e (or eps 1e-4))
  (or (> (math.abs (- a.x b.x)) e)
      (> (math.abs (- a.y b.y)) e)
      (> (math.abs (- a.z b.z)) e)))

(fn quat-changed? [a b eps]
  (local e (or eps 1e-4))
  (or (> (math.abs (- a.w b.w)) e)
      (> (math.abs (- a.x b.x)) e)
      (> (math.abs (- a.y b.y)) e)
      (> (math.abs (- a.z b.z)) e)))

(fn vec3->bt [value]
  (bt.Vector3 value.x value.y value.z))

(fn build-shape-data [record]
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local sample-spacing (HeightfieldTerrainGrid.spacing record))
  (local spacing-x (. sample-spacing 1))
  (local spacing-z (. sample-spacing 2))
  (local chunk-map (HeightfieldTerrainGrid.build-chunk-map record))
  (local heights [])
  (var min-height math.huge)
  (var max-height (- math.huge))
  (for [sample-z bounds.min-sample-z bounds.max-sample-z]
    (for [sample-x bounds.min-sample-x bounds.max-sample-x]
      (local height
        (HeightfieldTerrainGrid.sample-height-global record chunk-map sample-x sample-z))
      (assert (not (= height nil))
              "HeightfieldTerrain physics requires contiguous chunk coverage for btHeightfieldTerrainShape")
      (table.insert heights height)
      (when (< height min-height)
        (set min-height height))
      (when (> height max-height)
        (set max-height height))))
  {:width bounds.width
   :length bounds.length
   :heights heights
   :min-height min-height
   :max-height max-height
   :spacing-x spacing-x
   :spacing-z spacing-z
   :center-offset (glm.vec3 (* 0.5 (- bounds.width 1) spacing-x)
                            (* 0.5 (+ min-height max-height))
                            (* 0.5 (- bounds.length 1) spacing-z))})

(fn transform-for-layout [shape-data position rotation]
  (local transform (bt.Transform))
  (transform:setIdentity)
  (local world-origin
    (+ position
       (rotation:rotate shape-data.center-offset)))
  (transform:setOrigin (vec3->bt world-origin))
  (transform:setRotation (bt.Quaternion rotation.x rotation.y rotation.z rotation.w))
  transform)

(fn sync-moved-body [body]
  (when (and body app.engine.physics app.engine.physics.syncMovedRigidBody)
    (app.engine.physics:syncMovedRigidBody body)))

(fn create-heightfield [record]
  (when bt
    (local shape-data (build-shape-data record))
    (local position (HeightfieldTerrainSpace.resolve-position record))
    (local rotation (HeightfieldTerrainSpace.resolve-rotation record))
    (local restitution (or record.options.physics-restitution 1.0))
    (local shape (bt.HeightfieldTerrainShape shape-data.width
                                             shape-data.length
                                             shape-data.heights
                                             shape-data.min-height
                                             shape-data.max-height
                                             1
                                             false))
    (shape:setLocalScaling (bt.Vector3 shape-data.spacing-x 1.0 shape-data.spacing-z))
    (shape:buildAccelerator)
    (local layout-position
      (HeightfieldTerrainSpace.runtime-layout-position record position rotation))
    (local transform (transform-for-layout shape-data layout-position rotation))
    (local motion-state (bt.DefaultMotionState transform))
    (local zero (bt.Vector3 0 0 0))
    (local info (bt.RigidBodyConstructionInfo 0 motion-state shape zero))
    (set info.m-restitution restitution)
    (local body (bt.RigidBody info))
    (app.engine.physics:addRigidBody body)
    (local entry {:shape-data shape-data
                  :shape shape
                  :motion-state motion-state
                  :body body
                  :last-layout-position layout-position
                  :last-layout-rotation rotation})
    (set entry.sync-layout-transform
         (fn [self layout-position layout-rotation]
           (local next-position (or layout-position self.last-layout-position))
           (local next-rotation (or layout-rotation self.last-layout-rotation))
           (when (or (not self.last-layout-position)
                     (not self.last-layout-rotation)
                     (vec3-changed? self.last-layout-position next-position)
                     (quat-changed? self.last-layout-rotation next-rotation))
             (local next-transform
               (transform-for-layout self.shape-data next-position next-rotation))
             (self.body:setWorldTransform next-transform)
             (self.motion-state:setWorldTransform next-transform)
             (sync-moved-body self.body)
             (set self.last-layout-position next-position)
             (set self.last-layout-rotation next-rotation))))
    (set entry.drop
         (fn [self]
           (when (and self.body app.engine.physics)
             (app.engine.physics:removeRigidBody self.body))
           (set self.body nil)))
    entry))

{:create-heightfield create-heightfield}

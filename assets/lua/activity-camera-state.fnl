(local glm (require :glm))
(local Camera (require :camera))
(local MathUtils (require :math-utils))
(local CoordinateGuard (require :coordinate-guard))

(local vec3->array MathUtils.vec3->array)
(local quat->array MathUtils.quat->array)
(local array->vec3 MathUtils.array->vec3)
(local array->quat MathUtils.array->quat)
(local safe-vec3? CoordinateGuard.safe-vec3?)
(local sanitize-vec3 CoordinateGuard.sanitize-vec3)

(local ActivityCameraState {})

(fn ActivityCameraState.camera-from-state [camera-state defaults]
  "Create a Camera from a persisted camera-state table {:position [x y z] :rotation [w x y z]}.
   Falls back to defaults.position for the starting position when camera-state is missing or invalid."
  (local options (or defaults {}))
  (local default-position (or options.position (glm.vec3 0 0 0)))
  (local raw-position (and camera-state camera-state.position))
  (local position
    (if (= (type raw-position) :table)
        (let [(ok parsed) (pcall array->vec3 raw-position)]
          (if ok
              (sanitize-vec3 parsed default-position)
              default-position))
        default-position))
  (local raw-rotation (and camera-state camera-state.rotation))
  (local rotation
    (if (= (type raw-rotation) :table)
        (let [(ok parsed) (pcall array->quat raw-rotation)]
          (if ok parsed nil))
        nil))
  (local camera (Camera {:position position}))
  (when rotation
    (camera:set-rotation rotation))
  camera)

(fn ActivityCameraState.capture-camera [camera]
  "Capture a camera's position and rotation into a serializable table.
   Returns nil when camera is nil."
  (when camera
    (local state {:position (vec3->array camera.position)})
    (when camera.rotation
      (set state.rotation (quat->array camera.rotation)))
    state))

(fn ActivityCameraState.restore-camera! [camera camera-state]
  "Restore a camera's position and rotation from a serializable table.
   Returns true after restoring."
  (assert camera "ActivityCameraState.restore-camera! requires a camera")
  (when camera-state
    (when camera-state.position
      (let [(ok position) (pcall array->vec3 camera-state.position)]
        (when (and ok (safe-vec3? position))
          (camera:set-position position))))
    (when camera-state.rotation
      (let [(ok rotation) (pcall array->quat camera-state.rotation)]
        (when ok
          (camera:set-rotation rotation)))))
  true)

ActivityCameraState

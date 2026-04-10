(local glm (require :glm))
(local DrawingController (require :drawing/controller))
(local {:DrawingRender DrawingRender} (require :drawing/render))

(local tests [])

(fn make-vector-buffer []
  (local state {:allocations 0
                :deletes 0
                :vec3-writes 0
                :vec4-writes 0
                :float-writes 0
                :last-size nil
                :last-handle nil})
  (local buffer {})
  (set buffer.allocate
       (fn [_self count]
         (set state.allocations (+ state.allocations 1))
         (set state.last-size count)
         (set state.last-handle (+ state.allocations 100))
         state.last-handle))
  (set buffer.delete
       (fn [_self handle]
         (assert (= handle state.last-handle)
                 "drawing render should delete the tracked triangle handle")
         (set state.deletes (+ state.deletes 1))))
  (set buffer.set-glm-vec3
       (fn [_self handle _offset value]
         (assert (= handle state.last-handle)
                 "drawing render should write positions to the current triangle handle")
         (assert (= (type value.x) :number))
         (set state.vec3-writes (+ state.vec3-writes 1))))
  (set buffer.set-glm-vec4
       (fn [_self handle _offset value]
         (assert (= handle state.last-handle)
                 "drawing render should write colors to the current triangle handle")
         (assert (= (type value.x) :number))
         (set state.vec4-writes (+ state.vec4-writes 1))))
  (set buffer.set-float
       (fn [_self handle _offset value]
         (assert (= handle state.last-handle)
                 "drawing render should write depths to the current triangle handle")
         (assert (= (type value) :number))
         (set state.float-writes (+ state.float-writes 1))))
  (set buffer.state state)
  buffer)

(fn drawing-render-populates-triangle-buffer []
  (local track-log [])
  (local vector (make-vector-buffer))
  (local ctx {:triangle-vector vector
              :track-triangle-handle (fn [_self handle clip]
                                       (table.insert track-log {:handle handle
                                                                :clip clip}))
              :untrack-triangle-handle (fn [_self handle]
                                         (table.insert track-log {:untracked handle}))})
  (local controller (DrawingController {}))
  (controller:begin-gesture "rectangle" (glm.vec3 0 0 0))
  (controller:update-gesture (glm.vec3 24 12 0) false)
  (assert (controller:commit-gesture)
          "drawing render regression test expected rectangle commit to succeed")
  (local render (DrawingRender {:ctx ctx
                                :controller controller}))

  (render:update)

  (assert (> vector.state.last-size 0)
          "drawing render should allocate triangle storage for committed objects")
  (assert (> vector.state.vec3-writes 0)
          "drawing render should write vertex positions into the triangle buffer")
  (assert (= vector.state.vec3-writes vector.state.vec4-writes)
          "drawing render should write one color per vertex")
  (assert (= vector.state.vec3-writes vector.state.float-writes)
          "drawing render should write one depth per vertex")
  (assert (= (length track-log) 1)
          "drawing render should register the uploaded triangle handle once")
  (assert (= (. (. track-log 1) :handle) vector.state.last-handle)
          "drawing render should track the same handle it uploads")

  (render:drop)
  (assert (= vector.state.deletes 1)
          "drawing render should release the triangle handle on drop")
  (assert (= (length track-log) 2)
          "drawing render should untrack the triangle handle on drop")
  (assert (= (. (. track-log 2) :untracked) vector.state.last-handle)
          "drawing render should untrack the uploaded handle"))

(table.insert tests {:name "Drawing render uploads triangle data for committed objects"
                     :fn drawing-render-populates-triangle-buffer})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "drawing-render"
                       :tests tests})))

{:name "drawing-render"
 :tests tests
 :main main}

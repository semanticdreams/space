;; E2E snapshot test: renders colored shapes (red triangle + green rectangle) and verifies
;; the render pipeline produces correct pixel output.
;; Run: SPACE_SNAPSHOT_UPDATE=render-smoke make test-e2e (via e2e.fnl)

(local Harness (require :tests.e2e.harness))
(local RenderCapture (require :render-capture))
(local glm (require :glm))

(fn pixel-at [png x y]
  (local offset (+ (* (+ (* y png.width) x) 4) 1))
  {:r (string.byte png.bytes offset)
   :g (string.byte png.bytes (+ offset 1))
   :b (string.byte png.bytes (+ offset 2))
   :a (string.byte png.bytes (+ offset 3))})

(fn run [ctx]
  (local layout-lib (require :layout))
  (local dummy-builder (fn [_]
                         {:layout (layout-lib.Layout {:name "dummy" :measurer (fn [_] (glm.vec3 0 0 0)) :layouter (fn [_] nil)})
                          :drop (fn [_] true)}))

  (local target (Harness.make-screen-target {:width ctx.width :height ctx.height
                                              :world-units-per-pixel ctx.units-per-pixel
                                              :builder dummy-builder}))
  (local bctx target.build-context)
  (var h nil)
  (var h2 nil)

  (fn cleanup! []
    (when h
      (bctx:untrack-triangle-handle h)
      (bctx.triangle-vector:delete h))
    (when h2
      (bctx:untrack-triangle-handle h2)
      (bctx.triangle-vector:delete h2))
    (Harness.cleanup-target target))

  (local (ok err)
    (pcall
      (fn []
        ;; Upload a big red triangle covering the top-left quadrant
        (set h (bctx.triangle-vector:allocate (* 3 8)))
        (bctx.triangle-vector:set-glm-vec3 h 0 (glm.vec3 2 2 0))
        (bctx.triangle-vector:set-glm-vec4 h 3 (glm.vec4 1.0 0.2 0.2 1.0))
        (bctx.triangle-vector:set-float h 7 0.5)
        (bctx.triangle-vector:set-glm-vec3 h 8 (glm.vec3 30 2 0))
        (bctx.triangle-vector:set-glm-vec4 h 11 (glm.vec4 1.0 0.2 0.2 1.0))
        (bctx.triangle-vector:set-float h 15 0.5)
        (bctx.triangle-vector:set-glm-vec3 h 16 (glm.vec3 2 16 0))
        (bctx.triangle-vector:set-glm-vec4 h 19 (glm.vec4 1.0 0.2 0.2 1.0))
        (bctx.triangle-vector:set-float h 23 0.5)
        (bctx:track-triangle-handle h nil)

        ;; A green rectangle (2 triangles) in the top-right
        (set h2 (bctx.triangle-vector:allocate (* 6 8)))
        ;; Triangle 1: top-left, top-right, bottom-left
        (bctx.triangle-vector:set-glm-vec3 h2 0 (glm.vec3 18 10 0))
        (bctx.triangle-vector:set-glm-vec4 h2 3 (glm.vec4 0.2 1.0 0.2 1.0))
        (bctx.triangle-vector:set-float h2 7 0.5)
        (bctx.triangle-vector:set-glm-vec3 h2 8 (glm.vec3 28 10 0))
        (bctx.triangle-vector:set-glm-vec4 h2 11 (glm.vec4 0.2 1.0 0.2 1.0))
        (bctx.triangle-vector:set-float h2 15 0.5)
        (bctx.triangle-vector:set-glm-vec3 h2 16 (glm.vec3 18 16 0))
        (bctx.triangle-vector:set-glm-vec4 h2 19 (glm.vec4 0.2 1.0 0.2 1.0))
        (bctx.triangle-vector:set-float h2 23 0.5)
        ;; Triangle 2: top-right, bottom-left, bottom-right
        (bctx.triangle-vector:set-glm-vec3 h2 24 (glm.vec3 28 10 0))
        (bctx.triangle-vector:set-glm-vec4 h2 27 (glm.vec4 0.2 1.0 0.2 1.0))
        (bctx.triangle-vector:set-float h2 31 0.5)
        (bctx.triangle-vector:set-glm-vec3 h2 32 (glm.vec3 18 16 0))
        (bctx.triangle-vector:set-glm-vec4 h2 35 (glm.vec4 0.2 1.0 0.2 1.0))
        (bctx.triangle-vector:set-float h2 39 0.5)
        (bctx.triangle-vector:set-glm-vec3 h2 40 (glm.vec3 28 16 0))
        (bctx.triangle-vector:set-glm-vec4 h2 43 (glm.vec4 0.2 1.0 0.2 1.0))
        (bctx.triangle-vector:set-float h2 47 0.5)
        (bctx:track-triangle-handle h2 nil)

        ;; Draw
        (Harness.draw-targets ctx.width ctx.height [{:target target}])

        ;; Capture snapshot for golden comparison
        (Harness.capture-snapshot {:name "render-smoke" :width ctx.width :height ctx.height :tolerance 2})

        ;; Pixel verification
        (local capture (RenderCapture.capture {:mode "final" :width ctx.width :height ctx.height :return-bytes true}))
        (local png {:width ctx.width :height ctx.height :channels 4 :bytes capture.bytes})
        (local upp ctx.units-per-pixel)

        (fn world-to-screen [wx wy]
          (values (math.floor (/ wx upp))
                  (math.floor (- ctx.height (/ wy upp)))))

        ;; Red triangle region (world ~10, 9)
        (local (rx ry) (world-to-screen 10 9))
        (local cp (pixel-at png rx ry))
        (print (string.format "  red region (%d,%d): r=%d g=%d b=%d a=%d" rx ry cp.r cp.g cp.b cp.a))
        (assert (> cp.r 150) (.. "red region should be red, got r=" cp.r))

        ;; Green rectangle region (world ~23, 13)
        (local (gx gy) (world-to-screen 23 13))
        (local gp (pixel-at png gx gy))
        (print (string.format "  green region (%d,%d): r=%d g=%d b=%d a=%d" gx gy gp.r gp.g gp.b gp.a))
        (assert (> gp.g 150) (.. "green region should be green, got g=" gp.g))

        ;; Corner should be dark
        (local bp (pixel-at png 10 10))
        (assert (< bp.r 30) (.. "corner should be dark, got r=" bp.r))

        (print "  All pixel assertions passed"))))

  (cleanup!)
  (when (not ok)
    (error err)))

(fn main []
  (Harness.with-app {:width 640 :height 360} (fn [ctx] (run ctx)))
  (print "E2E render-smoke snapshot complete"))

{:main main}

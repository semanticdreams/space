(local _ (require :main))
(local ScrollWidget (require :next-app/scroll-widget))
(local PanelWidget (require :next-app/panel-widget))
(local TextWidget (require :next-app/text-widget))
(local NextLayout (require :next-app/layout))
(local QuadBatcher (require :next-app/quad-batcher))
(local TextSsboBatcher (require :text-ssbo-batcher))
(local glm (require :glm))

(local tests [])

(fn make-test-font []
  {:metadata {:atlas {:distanceRange 4
                      :width 256
                      :height 256}
              :metrics {:ascender 1.0
                        :descender -0.2
                        :lineHeight 1.2}}
   :texture {:id 1 :ready true}
   :glyph-map {(string.byte "i") {:planeBounds {:left 0 :right 0.35 :bottom -0.2 :top 0.8}
                                  :atlasBounds {:left 0 :right 35 :bottom 0 :top 80}
                                  :advance 0.37}
               (string.byte "t") {:planeBounds {:left 0 :right 0.42 :bottom -0.2 :top 0.8}
                                  :atlasBounds {:left 35 :right 77 :bottom 0 :top 80}
                                  :advance 0.44}
               (string.byte "e") {:planeBounds {:left 0 :right 0.50 :bottom -0.2 :top 0.8}
                                  :atlasBounds {:left 77 :right 127 :bottom 0 :top 80}
                                  :advance 0.52}
               (string.byte "m") {:planeBounds {:left 0 :right 0.62 :bottom -0.2 :top 0.8}
                                  :atlasBounds {:left 127 :right 189 :bottom 0 :top 80}
                                  :advance 0.64}
               65533 {:planeBounds {:left 0 :right 0.5 :bottom -0.2 :top 0.8}
                      :atlasBounds {:left 189 :right 239 :bottom 0 :top 80}
                      :advance 0.52}}})

(fn matrix-different? [a b]
  (local samples [(glm.vec4 0 0 0 1)
                  (glm.vec4 1 0 0 1)
                  (glm.vec4 0 1 0 1)])
  (var different false)
  (each [_ p (ipairs samples)]
    (local pa (* a p))
    (local pb (* b p))
    (when (or (> (math.abs (- pa.x pb.x)) 1e-5)
              (> (math.abs (- pa.y pb.y)) 1e-5)
              (> (math.abs (- pa.z pb.z)) 1e-5))
      (set different true)))
  different)

(fn next-app-rotated-nested-clip-affects-quad-and-text-paths []
  (local text-style {:font (make-test-font)
                     :scale 0.05
                     :color (glm.vec4 1 1 1 1)})
  (local text-a (TextWidget {:name "clip-stress-text-a"
                             :text "item"
                             :style text-style}))
  (local panel-a (PanelWidget {:name "clip-stress-panel-a"
                               :padding [0.02 0.02]
                               :child text-a
                               :color (glm.vec4 0.2 0.3 0.5 1)}))
  (local scroll-a (ScrollWidget {:name "clip-stress-scroll-a"
                                 :child panel-a
                                 :width 1.0
                                 :height 0.4}))

  (local text-b (TextWidget {:name "clip-stress-text-b"
                             :text "item"
                             :style text-style}))
  (local panel-b (PanelWidget {:name "clip-stress-panel-b"
                               :padding [0.02 0.02]
                               :child text-b
                               :color (glm.vec4 0.2 0.3 0.5 1)}))
  (local scroll-b (ScrollWidget {:name "clip-stress-scroll-b"
                                 :child panel-b
                                 :width 1.0
                                 :height 0.4}))

  (scroll-a:set-local-position -0.4 -0.2 0 (glm.quat 0.25 (glm.vec3 0 0 1)))
  (scroll-b:set-local-position 0.4 -0.2 0 (glm.quat 0.25 (glm.vec3 0 0 1)))
  (NextLayout.run-frame scroll-a 1.0 0.4 0)
  (NextLayout.run-frame scroll-b 1.0 0.4 0)

  (local parent-clip (glm.mat4-trs-z 0.15 -0.09 0 0.5235987756))

  (local local-clip (scroll-a:get-clip-matrix nil))
  (local composed-clip (scroll-b:get-clip-matrix parent-clip))
  (assert (matrix-different? local-clip composed-clip)
          "nested rotated parent clip should alter composed clip")

  (local quad-batcher (QuadBatcher {}))
  (quad-batcher:begin-frame)
  (panel-a:emit-quads quad-batcher local-clip)
  (panel-b:emit-quads quad-batcher composed-clip)
  (quad-batcher:end-frame)
  (assert (= (quad-batcher:get-clip-count) 3)
          "quad path should keep distinct local/composed clip groups")

  (local text-batcher (TextSsboBatcher {}))
  (text-batcher:begin-frame)
  (text-a:emit-ssbo text-batcher local-clip)
  (text-b:emit-ssbo text-batcher composed-clip)
  (text-batcher:end-frame)
  (local draws (text-batcher:get-draw-list))
  (assert (> (# draws) 0)
          "text path should produce at least one draw bucket")
  (var total-clip-floats 0)
  (var total-group-clip-count 0)
  (each [_ entry (ipairs draws)]
    (set total-clip-floats (+ total-clip-floats (entry.clip-vector:length)))
    (set total-group-clip-count (+ total-group-clip-count (entry.group-clip-index-vector:length))))
  (assert (>= total-clip-floats 32)
          "text path should store local and composed clip matrices")
  (assert (>= total-group-clip-count 2)
          "text path should map both groups to clip indices"))

(table.insert tests {:name "NextApp clip stress covers rotated nested clips for quad and text"
                     :fn next-app-rotated-nested-clip-affects-quad-and-text-paths})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-app-clip-stress"
                       :tests tests})))

{:name "next-app-clip-stress"
 :tests tests
 :main main}

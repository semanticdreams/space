(local glm (require :glm))
(local NextLayout (require :next-app/layout))
(local CuboidWidget (require :next-app/cuboid-widget))

(local tests [])

(fn approx [a b]
  (< (math.abs (- a b)) 1e-5))

(fn approx3 [ax ay az bx by bz]
  (and (approx ax bx)
       (approx ay by)
       (approx az bz)))

(fn quat-approx [a b]
  (and (approx a.w b.w)
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn approx-frame [frame x y z w h d rotation]
  (and frame
       (approx3 frame.x frame.y frame.z x y z)
       (approx3 frame.w frame.h frame.d w h d)
       (quat-approx frame.rotation rotation)))

(fn probe-node [name measured-width measured-height measured-depth]
  (local state {:layout-calls 0
                :last-frame nil})
  (local node
    (NextLayout.Node.new
      {:name name
       :measure-fn (fn [self _mw _mh _md]
                     (self:set-measure measured-width measured-height measured-depth))
       :layout-fn (fn [self width height depth]
                    (set state.layout-calls (+ state.layout-calls 1))
                    (set state.last-frame {:x self.local-x
                                           :y self.local-y
                                           :z self.local-z
                                           :w width
                                           :h height
                                           :d depth
                                           :rotation self.local-rotation})
                    (self:set-size width height depth {:mark-dirty? false}))}))
  {:node node :state state})

(fn cuboid-widget-measures-envelope []
  (local probes
    [(probe-node "f1" 8 9 0)
     (probe-node "f2" 10 7 0)
     (probe-node "f3" 12 11 0)
     (probe-node "f4" 9 5 0)
     (probe-node "f5" 6 3 0)
     (probe-node "f6" 4 2 0)])
  (local cuboid
    (CuboidWidget {:children (icollect [_ p (ipairs probes)] p.node)}))
  (NextLayout.run-frame cuboid 40 30 20)
  (assert (approx cuboid.measured-width 10))
  (assert (approx cuboid.measured-height 11))
  (assert (approx cuboid.measured-depth 12)))

(fn cuboid-widget-lays-out-six-faces []
  (local probes
    [(probe-node "f1" 1 1 1)
     (probe-node "f2" 1 1 1)
     (probe-node "f3" 1 1 1)
     (probe-node "f4" 1 1 1)
     (probe-node "f5" 1 1 1)
     (probe-node "f6" 1 1 1)])
  (local cuboid
    (CuboidWidget {:children (icollect [_ p (ipairs probes)] p.node)}))
  (NextLayout.run-frame cuboid 4 3 2)

  (assert (approx-frame (. (. probes 1) :state :last-frame) 0 0 2 4 3 2 (glm.quat 1 0 0 0)))
  (assert (approx-frame (. (. probes 2) :state :last-frame) 4 0 0 4 3 2 (glm.quat math.pi (glm.vec3 0 1 0))))
  (assert (approx-frame (. (. probes 3) :state :last-frame) 4 0 2 2 3 4 (glm.quat (* 0.5 math.pi) (glm.vec3 0 1 0))))
  (assert (approx-frame (. (. probes 4) :state :last-frame) 0 0 0 2 3 4 (glm.quat (* 1.5 math.pi) (glm.vec3 0 1 0))))
  (assert (approx-frame (. (. probes 5) :state :last-frame) 0 3 2 4 2 3 (glm.quat (* 1.5 math.pi) (glm.vec3 1 0 0))))
  (assert (approx-frame (. (. probes 6) :state :last-frame) 0 0 0 4 2 3 (glm.quat (* 0.5 math.pi) (glm.vec3 1 0 0)))))

(table.insert tests {:name "Next cuboid widget measures envelope"
                     :fn cuboid-widget-measures-envelope})
(table.insert tests {:name "Next cuboid widget lays out face transforms"
                     :fn cuboid-widget-lays-out-six-faces})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-app-cuboid-widget"
                       :tests tests})))

{:name "next-app-cuboid-widget"
 :tests tests
 :main main}

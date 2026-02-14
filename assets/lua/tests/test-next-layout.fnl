(local NextLayout (require :next-app/layout))
(local FlexModule (require :next-app/flex))
(local glm (require :glm))

(local tests [])

(fn approx [a b]
  (< (math.abs (- a b)) 1e-5))

(fn matrix-position [m]
  (local p (* m (glm.vec4 0 0 0 1)))
  (glm.vec2 p.x p.y))

(fn fixed-node [w h]
  (NextLayout.Node.new
    {:name "fixed-node-v2"
     :measure-fn (fn [self _mw _mh _md]
                   (self:set-measure w h 0))}))

(fn next-layout-transform-pass-multiplies-local-matrices []
  (local root (NextLayout.Node.new {:name "root-v2"}))
  (local child (NextLayout.Node.new {:name "child-v2"}))
  (root:add-child child)
  (root:set-frame 10 20 0 100 50 0 (glm.quat 1 0 0 0))
  (child:set-frame 2 3 0 4 5 0 (glm.quat 1 0 0 0))
  (root:transform-pass nil)

  (local world-pos (matrix-position child.world-matrix))
  (local render-x (* child.render-matrix (glm.vec4 1 0 0 1)))
  (local render-y (* child.render-matrix (glm.vec4 0 1 0 1)))
  (assert (approx world-pos.x 12))
  (assert (approx world-pos.y 23))
  (assert (approx (- render-x.x world-pos.x) 4))
  (assert (approx (- render-y.y world-pos.y) 5)))

(fn next-flex-layout-distributes-grow-and-cross-stretch []
  (local a (fixed-node 4 2))
  (local b (fixed-node 3 1))
  (local flex
    (FlexModule.Flex
      {:axis :x
       :gap 1
       :align-cross :stretch
       :children [(FlexModule.FlexChild a 0)
                  (FlexModule.FlexChild b 1)]}))

  (NextLayout.run-frame flex 20 6 0)

  (assert (approx a.width 4))
  (assert (approx b.width 15))
  (assert (approx a.height 6))
  (assert (approx b.height 6))
  (assert (approx a.local-x 0))
  (assert (approx b.local-x 5))
  (local pos (matrix-position b.world-matrix))
  (assert (approx pos.x 5)))

(fn next-layout-dirt-tracking-skips-clean-phases []
  (local counts {:measure 0 :layout 0})
  (local leaf
    (NextLayout.Node.new
      {:name "dirty-leaf-v2"
       :measure-fn (fn [self _mw _mh _md]
                     (set counts.measure (+ counts.measure 1))
                     (self:set-measure 2 1 0))
       :layout-fn (fn [self width height depth]
                    (set counts.layout (+ counts.layout 1))
                    (self:set-size width height depth {:mark-dirty? false}))}))
  (local root
    (NextLayout.Node.new
      {:name "dirty-root-v2"
       :layout-fn (fn [self width height depth]
                    (self:set-size width height depth {:mark-dirty? false})
                    (leaf:run-layout-subtree leaf.measured-width leaf.measured-height leaf.measured-depth))}))
  (root:add-child leaf)

  (NextLayout.run-frame root 20 10 0)
  (assert (= counts.measure 1))
  (assert (= counts.layout 1))

  (NextLayout.run-frame root 20 10 0)
  (assert (= counts.measure 1))
  (assert (= counts.layout 1))

  (leaf:set-local-position 7 9 0 (glm.quat 1 0 0 0))
  (NextLayout.run-frame root 20 10 0)
  (assert (= counts.measure 1))
  (assert (= counts.layout 1))
  (local pos (matrix-position leaf.world-matrix))
  (assert (approx pos.x 7))
  (assert (approx pos.y 9))

  (leaf:mark-measure-dirty)
  (NextLayout.run-frame root 20 10 0)
  (assert (= counts.measure 2))
  (assert (= counts.layout 2)))

(fn next-layout-profile-captures-pass-stats []
  (local child
    (NextLayout.Node.new
      {:name "profile-child-v2"
       :measure-fn (fn [self _mw _mh _md]
                     (self:set-measure 1 1 0))
       :layout-fn (fn [self w h d]
                    (self:set-size w h d {:mark-dirty? false}))}))
  (local root
    (NextLayout.Node.new
      {:name "profile-root-v2"
       :measure-fn (fn [self _mw _mh _md]
                     (self:set-measure 4 4 0))
       :layout-fn (fn [self w h d]
                    (self:set-size w h d {:mark-dirty? false})
                    (child:set-frame 1 2 0 child.measured-width child.measured-height 0 (glm.quat 1 0 0 0) {:mark-dirty? false})
                    (child:run-layout-subtree child.width child.height child.depth))}))
  (root:add-child child)

  (local first (NextLayout.run-frame-profile root 10 10 0))
  (assert (> first.measure-nodes 0))
  (assert (> first.layout-nodes 0))
  (assert (> first.transform-nodes 0))

  (root:set-local-position 3 5 0 (glm.quat 1 0 0 0))
  (local second (NextLayout.run-frame-profile root 10 10 0))
  (assert (= second.measure-nodes 0))
  (assert (= second.layout-nodes 0))
  (assert (= second.transform-nodes 1))
  (local pos (matrix-position child.world-matrix))
  (assert (approx pos.x 4))
  (assert (approx pos.y 7)))

(table.insert tests {:name "NextLayout transform pass multiplies local matrices"
                     :fn next-layout-transform-pass-multiplies-local-matrices})
(table.insert tests {:name "NextFlex distributes grow and cross stretch"
                     :fn next-flex-layout-distributes-grow-and-cross-stretch})
(table.insert tests {:name "NextLayout dirt tracking skips clean phases"
                     :fn next-layout-dirt-tracking-skips-clean-phases})
(table.insert tests {:name "NextLayout profile captures pass stats"
                     :fn next-layout-profile-captures-pass-stats})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-layout"
                       :tests tests})))

{:name "next-layout"
 :tests tests
 :main main}

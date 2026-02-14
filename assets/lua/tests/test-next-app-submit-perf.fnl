(local NextLayout (require :next-app/layout))
(local NextFlex (require :next-app/flex))
(local QuadBatcher (require :next-app/quad-batcher))
(local TextSsboBatcher (require :text-ssbo-batcher))
(local PanelWidget (require :next-app/panel-widget))
(local TextWidget (require :next-app/text-widget))
(local glm (require :glm))

(local tests [])

(fn make-root []
  (local title (TextWidget {:name "submit-perf-title"
                            :text "Submit Perf"
                            :scale 0.06}))
  (local body (TextWidget {:name "submit-perf-body"
                           :text "steady frame should be zero write"
                           :scale 0.05}))
  (local panel
    (PanelWidget {:name "submit-perf-panel"
                  :padding [0.04 0.04]
                  :color (glm.vec4 0.12 0.14 0.20 0.95)
                  :child (NextFlex.Flex {:name "submit-perf-column"
                                         :axis :y
                                         :gap 0.03
                                         :children [(NextFlex.FlexChild title 0)
                                                    (NextFlex.FlexChild body 0)]})}))
  (local root
    (NextFlex.Flex {:name "submit-perf-root"
                    :axis :y
                    :children [(NextFlex.FlexChild panel 0)]}))
  (root:set-local-position -0.7 -0.6 0 0)
  root)

(fn submit-with-caches [root quad-batcher text-batcher subtree-cache transform-cache]
  (fn emit-subtree [node inherited-clip-matrix force-reemit]
    (local subtree-version (or node._subtree-render-version 0))
    (local transform-version (or node._transform-version 0))
    (local should-reemit
      (or force-reemit
          (not (= (. subtree-cache node) subtree-version))
          (not (= (. transform-cache node) transform-version))))
    (when should-reemit
      (var active-clip-matrix inherited-clip-matrix)
      (when (and node node.get-clip-matrix)
        (set active-clip-matrix (node:get-clip-matrix inherited-clip-matrix)))
      (when node.emit-quads
        (node:emit-quads quad-batcher active-clip-matrix))
      (when node.emit-ssbo
        (node:emit-ssbo text-batcher active-clip-matrix))
      (each [_ child (ipairs node.children)]
        (emit-subtree child active-clip-matrix should-reemit))
      (set (. subtree-cache node) subtree-version)
      (set (. transform-cache node) transform-version)))

  (quad-batcher:begin-frame)
  (text-batcher:begin-frame)
  (emit-subtree root nil false)
  (quad-batcher:end-frame)
  (text-batcher:end-frame)
  (local quad-stats (quad-batcher:get-last-stats))
  (local text-stats (text-batcher:get-last-stats))
  {:write-count (+ quad-stats.write-count text-stats.write-count)
   :upsert-count (+ quad-stats.upsert-count text-stats.upsert-count)})

(fn next-app-submit-skips-steady-frames-and-rebuilds-on-transform []
  (local root (make-root))
  (local quad-batcher (QuadBatcher {}))
  (local text-batcher (TextSsboBatcher {}))
  (local subtree-cache (setmetatable {} {:__mode "k"}))
  (local transform-cache (setmetatable {} {:__mode "k"}))

  (NextLayout.run-frame root 1.8 1.3 0)
  (local first (submit-with-caches root quad-batcher text-batcher subtree-cache transform-cache))
  (assert (> first.write-count 0))
  (assert (> first.upsert-count 0))

  (NextLayout.run-frame root 1.8 1.3 0)
  (local steady (submit-with-caches root quad-batcher text-batcher subtree-cache transform-cache))
  (assert (= steady.write-count 0)
          (.. "steady frame write-count should be zero, got " steady.write-count))
  (assert (= steady.upsert-count 0)
          (.. "steady frame upsert-count should be zero, got " steady.upsert-count))

  (root:set-local-position -0.63 -0.58 0 0)
  (NextLayout.run-frame root 1.8 1.3 0)
  (local transform-only (submit-with-caches root quad-batcher text-batcher subtree-cache transform-cache))
  (assert (> transform-only.write-count 0)
          "transform-only frame should rewrite instances")
  (assert (> transform-only.upsert-count 0)
          "transform-only frame should upsert instances"))

(table.insert tests {:name "NextApp submit skips steady frames and rebuilds on transform"
                     :fn next-app-submit-skips-steady-frames-and-rebuilds-on-transform})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-app-submit-perf"
                       :tests tests})))

{:name "next-app-submit-perf"
 :tests tests
 :main main}

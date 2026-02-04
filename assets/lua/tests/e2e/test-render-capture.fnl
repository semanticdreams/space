(local Harness (require :tests.e2e.harness))
(local RenderCapture (require :render-capture))
(local ImageIO (require :image-io))
(local Snapshots (require :snapshots))
(local fs (require :fs))

(fn max-byte-diff [expected actual]
  (local expected-len (string.len expected))
  (local actual-len (string.len actual))
  (assert (= expected-len actual-len))
  (var max-diff 0)
  (for [i 1 expected-len]
    (local a (string.byte expected i))
    (local b (string.byte actual i))
    (local diff (math.abs (- a b)))
    (when (> diff max-diff)
      (set max-diff diff)))
  max-diff)

(fn run [ctx]
  (local button-target
    (Harness.make-screen-target {:width ctx.width
                                 :height ctx.height
                                 :world-units-per-pixel ctx.units-per-pixel
                                 :builder (Harness.make-button-builder {:text "Capture"})}))
  (Harness.draw-targets ctx.width ctx.height [{:target button-target}])
  (Harness.capture-snapshot {:name "render-capture-final"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (local output-dir (fs.join-path "/tmp/space/tests" "render-capture"))
  (when (and fs fs.create-dirs)
    (fs.create-dirs output-dir))
  (local capture-path (fs.join-path output-dir "render-capture-final.png"))
  (RenderCapture.capture {:mode "final"
                          :path capture-path
                          :width ctx.width
                          :height ctx.height})
  (local snapshot (ImageIO.read-png (Snapshots.snapshot-path "render-capture-final")))
  (local capture (ImageIO.read-png capture-path))
  (assert (= snapshot.width capture.width))
  (assert (= snapshot.height capture.height))
  (assert (= snapshot.channels capture.channels))
  (local diff (max-byte-diff snapshot.bytes capture.bytes))
  (assert (<= diff 0) (.. "render capture mismatch: max diff " diff))
  (Harness.cleanup-target button-target))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E render capture snapshot complete"))

{:run run
 :main main}

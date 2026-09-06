(local Harness (require :tests.e2e.harness))
(local fs (require :fs))
(local glm (require :glm))
(local InputState (require :input-state-router))
(local {:FsFileViewerNode FsFileViewerNode} (require :graph/nodes/fs-file-viewer))
(local FsFileViewerNodeView (require :graph/view/views/fs-file-viewer))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "e2e-fs-file-viewer-virtual-input"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "viewer-" (os.time) "-" temp-counter)))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn write-temp-file [dir]
  (local path (fs.join-path dir "viewer.txt"))
  (fs.write-file path "abcdefghijklmnopqrstuvwxyz\nsecond line\n")
  (fs.absolute path))

(fn active-key-down [payload]
  (local state (assert (app.states:active-state) "E2E requires active app state"))
  (assert state.on-key-down "E2E active state requires on-key-down")
  (state:on-key-down payload))

(fn active-text-input [payload]
  (local state (assert (app.states:active-state) "E2E requires active app state"))
  (assert state.on-text-input "E2E active state requires on-text-input")
  (state:on-text-input payload))

(fn text-of [text-widget]
  (table.concat
    (icollect [_ codepoint (ipairs (text-widget:get-codepoints))]
      (utf8.char codepoint))
    ""))

(fn status-string [view]
  (text-of view.status-text))

(fn assert-caret-inside-input [input]
  (input.layout:layouter)
  (assert input.caret.visible? "file viewer caret should be visible")
  (local local-x (- input.caret.layout.position.x input.layout.position.x))
  (assert (>= local-x input.padding.x) "caret should be inside left input edge")
  (assert (<= local-x (- input.layout.size.x input.padding.x))
          "caret should be inside right input edge"))

(fn install-state-hud! [ctx]
  (local hud-target (Harness.make-hud-target {:width ctx.width
                                              :height ctx.height}))
  (app.states:set-hud-provider (fn [_states] hud-target))
  (app.states:set-focus-manager-provider (fn [_states] hud-target.focus-manager))
  hud-target)

(fn make-view-builder [node view-ref]
  (fn build-view [child-ctx]
    (set view-ref.view ((FsFileViewerNodeView node {}) child-ctx))
    view-ref.view))

(fn make-view-target [ctx node view-ref]
  (Harness.make-screen-target
    {:width ctx.width
     :height ctx.height
     :world-units-per-pixel ctx.units-per-pixel
     :builder (make-view-builder node view-ref)}))

(fn force-narrow-input-allocation [input]
  (set input.layout.size
       (glm.vec3 (+ (* 2 input.padding.x)
                    (* 6 input.column-width))
                 (+ (* 2 input.padding.y)
                    (* 3 input.line-height))
                 0))
  (input.layout:layouter))

(fn run [ctx]
  (local dir (make-temp-dir))
  (local file (write-temp-file dir))
  (local node (FsFileViewerNode {:path file}))
  (local view-ref {})
  (local hud-target (install-state-hud! ctx))
  (local target (make-view-target ctx node view-ref))
  (target:update)
  (local view view-ref.view)
  (assert view "E2E should build FsFileViewerNodeView")
  (assert view.virtual-input "file viewer should expose VirtualInput")
  (force-narrow-input-allocation view.virtual-input)
  (view.virtual-input:on-click {:row-index 1 :column 0})
  (assert (= (InputState.active-input) view.virtual-input)
          "click should focus file viewer VirtualInput")
  (assert (= (app.states:active-name) :text)
          "click should enter text state")
  (assert (active-key-down {:key (string.byte "i")})
          "Vim i should enter insert through active state")
  (assert (= (app.states:active-name) :insert)
          "active state should become insert")
  (assert (active-text-input {:text "i"})
          "insert-entering text event should be consumed through active insert state")
  (assert (active-text-input {:text "!"})
          "insert text should route through active insert state")
  (assert (active-key-down {:key 27})
          "escape should return to text mode")
  (assert (= (app.states:active-name) :text)
          "escape should return to text state")
  (for [_ 1 12]
    (active-key-down {:key (string.byte "l")}))
  (assert (> view.virtual-input.scroll-column 0)
          "long-line navigation should scroll horizontally")
  (assert-caret-inside-input view.virtual-input)
  (assert (active-key-down {:key (string.byte "s") :mod 64})
          "Ctrl+S should save through file viewer key route")
  (local saved-content (fs.read-file file))
  (assert (= saved-content "!abcdefghijklmnopqrstuvwxyz\nsecond line\n")
          (.. "saved file should contain routed insert edit, got: " saved-content))
  (assert (string.find (status-string view) "Saved" 1 true)
          "status should report saved")
  (Harness.cleanup-target target)
  (Harness.cleanup-target hud-target)
  (node:drop)
  (fs.remove-all dir))

(fn run-main [ctx]
  (run ctx))

(fn main []
  (Harness.with-app {:width 960 :height 720} run-main)
  (print "E2E fs file viewer VirtualInput usability complete"))

{:run run
 :main main}

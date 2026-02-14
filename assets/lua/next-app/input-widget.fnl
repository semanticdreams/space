(local glm (require :glm))
(local TextStyle (require :text-style))
(local {: codepoints-from-text} (require :text-utils))

(local NextLayout (require :next-app/layout))
(local Node NextLayout.Node)
(local PanelWidget (require :next-app/panel-widget))
(local TextWidget (require :next-app/text-widget))

(fn clamp [value low high]
  (math.max low (math.min high value)))

(fn world-position [node]
  (local p (* node.world-matrix (glm.vec4 0 0 0 1)))
  (glm.vec3 p.x p.y p.z))

(fn InputWidget [opts]
  (local options (or opts {}))
  (local focus-context options.focus)
  (local width (or options.width 0.9))
  (local height (or options.height 0.18))
  (local padding-x (or options.padding-x 0.04))
  (local padding-y (or options.padding-y 0.03))
  (local style
    (or options.style
        (TextStyle {:scale (or options.text-scale 0.05)
                    :color (or options.color (glm.vec4 0.95 0.95 0.98 1))})))

  (var text (or options.text ""))
  (var cursor-index (or options.cursor-index (# text)))
  (var focused? false)
  (var input nil)
  (var focus-node nil)
  (var focus-manager nil)
  (var focus-focus-listener nil)
  (var focus-blur-listener nil)

  (local background (PanelWidget {:name (or options.background-name "next-input-bg")
                                  :padding [0 0]
                                  :color (or options.background-color (glm.vec4 0.10 0.12 0.18 0.96))}))
  (local focus-ring (PanelWidget {:name (or options.focus-name "next-input-focus")
                                  :padding [0 0]
                                  :visible? false
                                  :color (or options.focus-color (glm.vec4 0.42 0.72 1.0 0.95))}))
  (local caret (PanelWidget {:name (or options.caret-name "next-input-caret")
                             :padding [0 0]
                             :visible? false
                             :color (or options.caret-color (glm.vec4 0.98 0.98 1 1))}))
  (local text-node (TextWidget {:name (or options.text-name "next-input-text")
                                :text text
                                :style style}))
  (local placeholder-node
    (TextWidget {:name (or options.placeholder-name "next-input-placeholder")
                 :text (or options.placeholder "Type to filter")
                 :style (TextStyle {:font style.font
                                    :scale style.scale
                                    :color (or options.placeholder-color (glm.vec4 0.62 0.65 0.72 0.8))})}))

  (fn cursor-x []
    (local cps (codepoints-from-text text))
    (local limit (clamp cursor-index 0 (length cps)))
    (var x 0)
    (for [i 1 limit]
      (local cp (. cps i))
      (local glyph (or (. style.font.glyph-map cp)
                       (. style.font.glyph-map 65533)))
      (set x (+ x (* glyph.advance style.scale))))
    x)

  (fn update-visual-state []
    (focus-ring:set-visible focused?)
    (caret:set-visible focused?)
    (placeholder-node:set-visible (= (# text) 0)))

  (fn set-focused [value]
    (set focused? (not (= value false)))
    (set input.focused? focused?)
    (update-visual-state))

  (fn measure-fn [self _mw _mh _md]
    (text-node:run-measure width height 0)
    (placeholder-node:run-measure width height 0)
    (self:set-measure width height 0))

  (fn layout-fn [self resolved-width resolved-height depth]
    (self:set-size resolved-width resolved-height depth {:mark-dirty? false})

    (focus-ring:layout-set-frame -0.01 -0.01 -0.003 (+ resolved-width 0.02) (+ resolved-height 0.02) 0 (glm.quat 1 0 0 0))
    (focus-ring:run-layout focus-ring.width focus-ring.height focus-ring.depth)

    (background:layout-set-frame 0 0 -0.001 resolved-width resolved-height 0 (glm.quat 1 0 0 0))
    (background:run-layout background.width background.height background.depth)

    (local text-width (math.max 0 (- resolved-width (* padding-x 2))))
    (local text-height (math.max 0 (- resolved-height (* padding-y 2))))
    (text-node:layout-set-frame padding-x padding-y -0.002 text-width text-height 0 (glm.quat 1 0 0 0))
    (text-node:run-layout text-node.width text-node.height text-node.depth)

    (placeholder-node:layout-set-frame padding-x padding-y -0.002 text-width text-height 0 (glm.quat 1 0 0 0))
    (placeholder-node:run-layout placeholder-node.width placeholder-node.height placeholder-node.depth)

    (local cx (+ padding-x (cursor-x)))
    (caret:layout-set-frame cx (+ padding-y 0.003) -0.0025 0.008 (math.max 0.02 (- text-height 0.006)) 0 (glm.quat 1 0 0 0))
    (caret:run-layout caret.width caret.height caret.depth)

    (update-visual-state))

  (set input
       (Node.new {:name (or options.name "next-input")
                  :measure-fn measure-fn
                  :layout-fn layout-fn}))
  (input:add-child focus-ring)
  (input:add-child background)
  (input:add-child text-node)
  (input:add-child placeholder-node)
  (input:add-child caret)

  (set input.text-node text-node)
  (set input.placeholder-node placeholder-node)
  (set input.caret caret)
  (set input.focused? focused?)

  (set input.set-text
       (fn [self value]
         (local next-text (or value ""))
         (when (not (= text next-text))
           (set text next-text)
           (set cursor-index (clamp cursor-index 0 (# text)))
           (text-node:set-text text)
           (self:mark-measure-dirty)
           (self:mark-layout-dirty)
           (update-visual-state))))

  (set input.get-text (fn [_self] text))

  (set input.move-cursor
       (fn [self delta]
         (set cursor-index (clamp (+ cursor-index delta) 0 (# text)))
         (self:mark-layout-dirty)))

  (set input.insert-text
       (fn [self value]
         (local chunk (or value ""))
         (local left (string.sub text 1 cursor-index))
         (local right (string.sub text (+ cursor-index 1)))
         (set text (.. left chunk right))
         (set cursor-index (+ cursor-index (# chunk)))
         (text-node:set-text text)
         (self:mark-measure-dirty)
         (self:mark-layout-dirty)
         (update-visual-state)))

  (set input.backspace
       (fn [self]
         (when (> cursor-index 0)
           (local left (string.sub text 1 (- cursor-index 1)))
           (local right (string.sub text (+ cursor-index 1)))
           (set text (.. left right))
           (set cursor-index (- cursor-index 1))
           (text-node:set-text text)
           (self:mark-measure-dirty)
           (self:mark-layout-dirty)
           (update-visual-state))))

  (set input.request-focus
       (fn [_self]
         (if focus-node
             (focus-node:request-focus {:reason :pointer})
             (set-focused true))))

  (set input.on-click
       (fn [self _event]
         (self:request-focus)
         (set cursor-index (# text))
         (self:mark-layout-dirty)))

  (set input.set-focused
       (fn [self value]
         (local next-focused (not (= value false)))
         (when (not (= focused? next-focused))
           (set-focused next-focused)
           (self:mark-layout-dirty))))

  (set input.emit-quads
       (fn [_self quad-batcher clip-matrix]
         (focus-ring:emit-quads quad-batcher clip-matrix)
         (background:emit-quads quad-batcher clip-matrix)
         (caret:emit-quads quad-batcher clip-matrix)))

  (set input.drop
       (fn [self]
         (when focus-focus-listener
           (when (and focus-manager focus-manager.focus-focus)
             (focus-manager.focus-focus.disconnect focus-focus-listener true))
           (set focus-focus-listener nil))
         (when focus-blur-listener
           (when (and focus-manager focus-manager.focus-blur)
             (focus-manager.focus-blur.disconnect focus-blur-listener true))
           (set focus-blur-listener nil))
         (when focus-node
           (focus-node:drop)
           (set focus-node nil)
           (set self.focus-node nil))))

  (when focus-context
    (set focus-node
         (focus-context:create-node {:name (or options.focus-node-name "next-input-focus-node")}))
    (set focus-manager (and focus-node focus-node.manager))
    (set input.focus-node focus-node)
    (set input.focus-manager focus-manager)
    (when (and focus-context focus-context.attach-bounds)
      (focus-context:attach-bounds focus-node
                                   {:get-focus-bounds (fn []
                                                        {:position (world-position input)
                                                         :size (glm.vec3 input.width input.height 0.01)})}))
    (when (and focus-manager focus-manager.focus-focus)
      (set focus-focus-listener
           (focus-manager.focus-focus.connect
             (fn [event]
               (when (and event (= event.current focus-node))
                 (set-focused true))))))
    (when (and focus-manager focus-manager.focus-blur)
      (set focus-blur-listener
           (focus-manager.focus-blur.connect
             (fn [event]
               (when (and event (= event.previous focus-node))
                 (set-focused false))))))
    (when (not focus-node.activate)
      (set focus-node.activate
           (fn [_node _opts]
             (input:request-focus)
             true))))

  input)

InputWidget

(local glm (require :glm))
(local ScrollView (require :scroll-view))
(local {: Flex : FlexChild} (require :flex))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Rectangle (require :rectangle))
(local Stack (require :stack))
(local Padding (require :padding))
(local Sized (require :sized))

(fn layout-center [layout]
  (+ layout.position
     (glm.vec3 (/ layout.size.x 2)
               (/ layout.size.y 2)
               0)))

(fn world-to-screen [ctx pos]
  {:x (/ pos.x ctx.units-per-pixel)
   :y (- ctx.height (/ pos.y ctx.units-per-pixel))})

(fn make-item-builder [label color style size]
  (fn [_ctx]
    (local rect (Rectangle {:color color}))
    (local text (Text {:text label :style style}))
    (local content (Padding {:edge-insets [0.4 0.3]
                             :child text}))
    (local stack (Stack {:children [rect content]}))
    ((Sized {:size size :child stack}) _ctx)))

(fn make-scroll-view-builder [opts]
  (local options (or opts {}))
  (local size (or options.size (glm.vec3 18 7 0)))
  (local item-size (or options.item-size (glm.vec3 14 2.2 0)))
  (local text-style (or options.text-style
                        (TextStyle {:scale 1.4
                                    :color (glm.vec4 0.94 0.96 0.98 1)})))
  (local colors
    (or options.colors
        [(glm.vec4 0.18 0.22 0.34 1)
         (glm.vec4 0.24 0.26 0.36 1)
         (glm.vec4 0.2 0.28 0.3 1)
         (glm.vec4 0.28 0.22 0.3 1)
         (glm.vec4 0.22 0.24 0.34 1)
         (glm.vec4 0.2 0.26 0.32 1)
         (glm.vec4 0.24 0.23 0.28 1)
         (glm.vec4 0.19 0.27 0.31 1)]))
  (local items (or options.items
                   ["Alpha" "Bravo" "Charlie" "Delta"
                    "Echo" "Foxtrot" "Golf" "Hotel"]))
  (var view nil)
  (local children [])
  (each [idx label (ipairs items)]
    (local color (. colors (+ (math.fmod (- idx 1) (length colors)) 1)))
    (table.insert children (FlexChild (make-item-builder label color text-style item-size) 0)))
  (local column (Flex {:axis :y
                       :reverse true
                       :yspacing 0.6
                       :xalign :start
                       :children children}))
  (local scroll-builder
    (fn [ctx]
      (local scroll ((ScrollView {:child column
                                  :scrollbar-width 0.7}) ctx))
      (set view scroll)
      scroll))
  (local background (Rectangle {:color (glm.vec4 0.08 0.09 0.12 1)}))
  (local stack (Stack {:children [background scroll-builder]}))
  (local sized (Sized {:size size :child stack}))
  {:builder (fn [ctx] (sized ctx))
   :get-view (fn [] view)})

(fn scrollbar-center-screen [ctx view]
  (assert (and view view.scrollbar view.scrollbar.layout) "scroll view missing scrollbar layout")
  (local center (layout-center view.scrollbar.layout))
  (world-to-screen ctx center))

{:make-scroll-view-builder make-scroll-view-builder
 :scrollbar-center-screen scrollbar-center-screen}

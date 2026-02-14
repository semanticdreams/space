(local glm (require :glm))

(fn matrix-position [matrix]
  (if (glm.is-mat4 matrix)
      (let [p (* matrix (glm.vec4 0 0 0 1))]
        (glm.vec3 p.x p.y p.z))
      (glm.vec3 (or (. matrix 13) 0)
                (or (. matrix 14) 0)
                (or (. matrix 15) 0))))

(local InteractionRouter {})
(set InteractionRouter.__index InteractionRouter)

(fn bounds-hit? [node x y]
  (if (and node node.world-matrix)
      (let [position (matrix-position node.world-matrix)
            left position.x
            top position.y
            right (+ left (or node.width 0))
            bottom (+ top (or node.height 0))]
        (and (>= x left) (<= x right) (>= y top) (<= y bottom)))
      false))

(fn remove-node [arr target]
  (var index nil)
  (each [i node (ipairs arr)]
    (when (= node target)
      (set index i)))
  (when index
    (table.remove arr index)))

(fn pick-topmost [arr x y]
  (var hit nil)
  (var hit-z -1e9)
  (each [_ node (ipairs arr)]
    (when (bounds-hit? node x y)
      (local position (matrix-position node.world-matrix))
      (local z position.z)
      (when (> z hit-z)
        (set hit node)
        (set hit-z z))))
  hit)

(fn InteractionRouter.new []
  (local self
    (setmetatable {:clickables []
                   :hoverables []
                   :active-hover nil}
                  InteractionRouter))

  (set self.register-clickable
       (fn [router node]
         (table.insert router.clickables node)
         node))

  (set self.unregister-clickable
       (fn [router node]
         (remove-node router.clickables node)))

  (set self.register-hoverable
       (fn [router node]
         (table.insert router.hoverables node)
         node))

  (set self.unregister-hoverable
       (fn [router node]
         (remove-node router.hoverables node)
         (when (= router.active-hover node)
           (set router.active-hover nil))))

  (set self.dispatch-click
       (fn [router x y event]
         (local target (pick-topmost router.clickables x y))
         (when (and target target.on-click)
           (target:on-click (or event {:x x :y y :source :next-app-router})))
         target))

  (set self.dispatch-hover
       (fn [router x y]
         (local target (pick-topmost router.hoverables x y))
         (when (not (= target router.active-hover))
           (when (and router.active-hover router.active-hover.on-hovered)
             (router.active-hover:on-hovered false))
           (set router.active-hover target)
           (when (and target target.on-hovered)
             (target:on-hovered true)))
         target))

  (set self.drop
       (fn [router]
         (set router.clickables [])
         (set router.hoverables [])
         (set router.active-hover nil)))

  self)

InteractionRouter

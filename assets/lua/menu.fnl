(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local {: Layout} (require :layout))
(local Button (require :button))

(fn resolve-action-name [action]
  (or action.name action.text (. action 1)))

(fn resolve-action-handler [action]
  (or action.on-click action.handler action.fn (. action 2)))

(fn normalize-actions [actions]
  (local normalized [])
  (each [_ entry (ipairs (or actions []))]
    (when (not (= (type entry) :table))
      (error "Menu actions must be provided as tables"))
    (local name (resolve-action-name entry))
    (assert name "Menu action is missing a name")
    (table.insert normalized
                  {:name name
                   :handler (resolve-action-handler entry)
                   :icon entry.icon
                   :variant entry.variant
                   :padding entry.padding}))
  normalized)

(fn Menu [opts]
  (local options (or opts {}))
  (local actions (normalize-actions options.actions))
  (local default-variant options.action-variant)
  (local default-padding options.action-padding)
  (local default-spacing (or options.content-spacing 1))
  (local min-width (or options.min-width 20))

  (fn build [ctx]
    (local buttons [])
    (local children
      (icollect [_ action (ipairs actions)]
        (FlexChild
          (fn [child-ctx]
            (local button
              ((Button {:text action.name
                        :icon action.icon
                        :content-spacing (or action.content-spacing default-spacing)
                        :variant (or action.variant default-variant)
                        :padding (or action.padding default-padding)
                        :on-click (if action.handler
                                      (fn [btn event]
                                        (action.handler btn event))
                                      nil)})
               child-ctx))
            (table.insert buttons button)
            button)
          0)))
    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0
              :children children})
       ctx))

    (fn measurer [self]
      (flex.layout:measurer)
      (local measure flex.layout.measure)
      (set self.measure (glm.vec3 (math.max (. measure 1) min-width)
                                  (. measure 2)
                                  (. measure 3))))

    (fn layouter [self]
      (local base-size (or self.size self.measure (glm.vec3 0 0 0)))
      (local size (glm.vec3 (math.max (. base-size 1) min-width)
                            (. base-size 2)
                            (. base-size 3)))
      (set self.size size)
      (set flex.layout.size size)
      (set flex.layout.position (+ self.position (glm.vec3 0 (- size.y) 0)))
      (set flex.layout.rotation self.rotation)
      (set flex.layout.depth-offset-index (+ self.depth-offset-index 1))
      (set flex.layout.clip-region self.clip-region)
      (flex.layout:layouter))

    (local layout
      (Layout {:name (or options.name "menu")
               :children [flex.layout]
               :measurer measurer
               :layouter layouter}))

    (fn drop [self]
      (self.layout:drop)
      (flex:drop))

    {:layout layout
     :buttons buttons
     :actions actions
     :drop drop}))

Menu

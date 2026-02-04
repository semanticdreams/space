(local glm (require :glm))
(local Image (require :image))
(local Text (require :text))
(local TextStyle (require :text-style))
(local {: Layout} (require :layout))

(fn Icon [opts]
  (local options (or opts {}))
  
  (fn build [ctx]
    (local icons (assert ctx.icons "Icon widget requires ctx.icons"))
    (local icon-ref (or options.icon options.name))
    (local resolved 
      (if (= (type icon-ref) :string)
          (icons:resolve icon-ref)
          icon-ref))
    
    (local color (or options.color (glm.vec4 1 1 1 1)))
    (local size (or options.size 24)) ;; Default pixel size assumption, though space units might be smaller
    
    (local child-widget
      (if (not resolved)
          (Text {:text "?" :style (TextStyle {:color (glm.vec4 1 0 0 1)})})
          (= resolved.type :font)
          (Text {:codepoints [resolved.codepoint]
                 :style (TextStyle {:color color
                                    :font resolved.font})})
          (= resolved.type :image)
          (Image {:path resolved.path
                  :tint color
                  :width options.width
                  :height options.height
                  :size (if (and (not options.width) (not options.height))
                             (glm.vec3 size size 0)
                             nil)})
          (Text {:text "?" :style (TextStyle {:color (glm.vec4 1 0 0 1)})})))

    (local child (child-widget ctx))

    (fn measurer [self]
      (child.layout:measurer)
      (set self.measure child.layout.measure))

    (fn layouter [self]
      (set child.layout.position self.position)
      (set child.layout.rotation self.rotation)
      (set child.layout.size self.size)
      (set child.layout.depth-offset-index self.depth-offset-index)
      (set child.layout.clip-region self.clip-region)
      (child.layout:layouter))

    (local layout
      (Layout {:name (or options.name "icon")
               :measurer measurer
               :layouter layouter
               :children [child.layout]}))

    (fn set-icon [self name opts]
      (local new-resolved (icons:resolve name))
      (if (and new-resolved (= new-resolved.type :font) child.set-codepoints)
          (child:set-codepoints [new-resolved.codepoint] opts)
          (do 
            ;; TODO: Handle switching between font/image or updating image path
            (print "Warning: Dynamic icon switching for non-font icons or type mismatch not fully implemented")
            nil)))

    {:layout layout
     :drop (fn [_] (child:drop))
     :set-icon set-icon
     :child child}))

Icon

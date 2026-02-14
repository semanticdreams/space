(local NextLayout (require :next-app/layout))
(local Node NextLayout.Node)

(fn normalize-axis [axis]
  (if (or (= axis :y) (= axis "y") (= axis 2))
      :y
      :x))

(fn normalize-align [align]
  (if (or (= align :center) (= align "center"))
      :center
      (if (or (= align :end) (= align "end"))
          :end
          (if (or (= align :stretch) (= align "stretch"))
              :stretch
              :start))))

(fn FlexChild [node grow]
  {:node node :grow (or grow 0)})

(fn Flex [opts]
  (local options (or opts {}))
  (local axis (normalize-axis options.axis))
  (local gap (or options.gap options.spacing 0))
  (local align-cross (normalize-align (or options.align-cross options.align :start)))
  (local entries [])
  (each [_ child (ipairs (or options.children []))]
    (table.insert entries {:node child.node :grow (or child.grow 0)}))

  (fn main-size [node]
    (if (= axis :x)
        node.measured-width
        node.measured-height))

  (fn cross-size [node]
    (if (= axis :x)
        node.measured-height
        node.measured-width))

  (fn set-child-frame [child main-pos cross-pos main-len cross-len]
    (if (= axis :x)
        (child:layout-set-frame main-pos cross-pos 0 main-len cross-len 0 0)
        (child:layout-set-frame cross-pos main-pos 0 cross-len main-len 0 0)))

  (fn measure-fn [self max-width max-height max-depth]
    (local count (length entries))
    (var main-total 0)
    (var cross-max 0)
    (each [_ entry (ipairs entries)]
      (local child entry.node)
      (child:run-measure-subtree max-width max-height max-depth)
      (set main-total (+ main-total (main-size child)))
      (local c (cross-size child))
      (when (> c cross-max)
        (set cross-max c)))
    (set main-total (+ main-total (* (math.max 0 (- count 1)) gap)))
    (if (= axis :x)
        (self:set-measure main-total cross-max 0)
        (self:set-measure cross-max main-total 0)))

  (fn layout-fn [self width height _depth]
    (local count (length entries))
    (local main-capacity (if (= axis :x) width height))
    (local cross-capacity (if (= axis :x) height width))
    (local total-gap (* (math.max 0 (- count 1)) gap))
    (local available-main (- main-capacity total-gap))
    (var fixed-main 0)
    (var grow-sum 0)

    (each [_ entry (ipairs entries)]
      (if (> entry.grow 0)
          (set grow-sum (+ grow-sum entry.grow))
          (set fixed-main (+ fixed-main (main-size entry.node)))))

    (local grow-space (math.max 0 (- available-main fixed-main)))
    (local temp-main [])
    (var total-main 0)
    (each [i entry (ipairs entries)]
      (local base (main-size entry.node))
      (local grow-extra (if (> grow-sum 0)
                            (* grow-space (/ entry.grow grow-sum))
                            0))
      (local resolved (if (> entry.grow 0) grow-extra base))
      (set (. temp-main i) resolved)
      (set total-main (+ total-main resolved)))

    (when (> total-main available-main)
      (local shrink (if (> total-main 0) (/ available-main total-main) 0))
      (for [i 1 count]
        (set (. temp-main i) (* (. temp-main i) shrink))))

    (var main-offset 0)
    (each [i entry (ipairs entries)]
      (local child entry.node)
      (local child-main (. temp-main i))
      (local child-cross
        (if (= align-cross :stretch)
            cross-capacity
            (cross-size child)))
      (local cross-offset
        (if (= align-cross :center)
            (/ (- cross-capacity child-cross) 2)
            (if (= align-cross :end)
                (- cross-capacity child-cross)
                0)))
      (set-child-frame child main-offset cross-offset child-main child-cross)
      (child:run-layout-subtree child.width child.height child.depth)
      (set main-offset (+ main-offset child-main gap))))

  (local flex-node
    (Node.new {:name (or options.name "next-flex")
               :measure-fn measure-fn
               :layout-fn layout-fn}))
  (each [_ entry (ipairs entries)]
    (flex-node:add-child entry.node))
  flex-node)

{:Flex Flex
 :FlexChild FlexChild}

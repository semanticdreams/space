(local glm (require :glm))
(local NextLayout (require :next-app/layout))
(local TextWidget (require :next-app/text-widget))

(local tests [])

(fn next-app-text-widget-measures-and-emits-codepoints []
  (local widget
    (TextWidget {:name "widget-under-test"
                 :text "AB"
                 :scale 0.04}))
  (NextLayout.run-frame widget 10 10 0)
  (assert (> widget.measured-width 0))
  (assert (> widget.measured-height 0))

  (var captured-key nil)
  (var captured nil)
  (local batcher {:upsert-text (fn [_self key payload]
                                 (set captured-key key)
                                 (set captured payload))
                  :update-text-transform (fn [_self _key _payload] nil)
                  :remove-text (fn [_self _key] nil)
                  :add-text (fn [_self payload]
                              (set captured payload))})
  (local clip-matrix
    [1 0 0 0
     0 1 0 0
     0 0 1 0
     0 0 0 1])
  (widget:emit-ssbo batcher clip-matrix)
  (assert captured "emit-ssbo should submit text payload")
  (assert (= captured-key widget) "emit-ssbo should key text by widget node")
  (assert captured.font "emit payload should include font")
  (assert (= (length captured.codepoints) 2))
  (assert captured.group-matrix "emit payload should include group matrix")
  (assert (glm.is-mat4 captured.group-matrix) "group matrix should be a glm.mat4")
  (assert (= captured.clip-matrix clip-matrix) "emit payload should forward clip matrix"))

(fn next-app-text-widget-set-text-marks-measure-dirty []
  (local widget
    (TextWidget {:name "widget-dirty"
                 :text "A"
                 :scale 0.04}))
  (NextLayout.run-frame widget 10 10 0)
  (assert (= widget._measure-dirty false))
  (widget:set-text "ABCD")
  (assert widget._measure-dirty "set-text should mark measure dirty")
  (NextLayout.run-frame widget 10 10 0)
  (assert (= widget._measure-dirty false))
  (assert (> widget.measured-width 0)))

(fn next-app-text-widget-measure-cache-invalidates-on-text-change []
  (local widget
    (TextWidget {:name "widget-cache"
                 :text "Cache"
                 :scale 0.04}))
  (assert (= (widget:_measure-cache-valid?) false))
  (NextLayout.run-frame widget 10 10 0)
  (assert (= (widget:_measure-cache-valid?) true))
  (widget:set-text "Cache + update")
  (assert (= (widget:_measure-cache-valid?) false))
  (NextLayout.run-frame widget 10 10 0)
  (assert (= (widget:_measure-cache-valid?) true)))

(fn next-app-text-widget-uses-transform-only-updates-when-content-is-clean []
  (local widget
    (TextWidget {:name "widget-transform-only"
                 :text "Stable"
                 :scale 0.04}))
  (NextLayout.run-frame widget 10 10 0)

  (var upsert-count 0)
  (var transform-count 0)
  (local batcher {:upsert-text (fn [_self key payload]
                                 (set upsert-count (+ upsert-count 1))
                                 (assert (= key widget))
                                 (assert payload.codepoints))
                  :update-text-transform (fn [_self key payload]
                                           (set transform-count (+ transform-count 1))
                                           (assert (= key widget))
                                           (assert payload.group-matrix))
                  :remove-text (fn [_self _key] nil)})
  (local clip-matrix
    [1 0 0 0
     0 1 0 0
     0 0 1 0
     0 0 0 1])
  (widget:emit-ssbo batcher clip-matrix)
  (assert (= upsert-count 1))
  (assert (= transform-count 0))

  (widget:set-local-position 0.1 0.2 0 0)
  (NextLayout.run-frame widget 10 10 0)
  (widget:emit-ssbo batcher clip-matrix)
  (assert (= upsert-count 1))
  (assert (= transform-count 1))

  (widget:set-text "Stable+")
  (NextLayout.run-frame widget 10 10 0)
  (widget:emit-ssbo batcher clip-matrix)
  (assert (= upsert-count 2))
  (assert (= transform-count 1)))

(fn next-app-text-widget-reupserts-when-batcher-instance-changes []
  (local widget
    (TextWidget {:name "widget-batcher-swap"
                 :text "Stable"
                 :scale 0.04}))
  (NextLayout.run-frame widget 10 10 0)
  (local clip-matrix
    [1 0 0 0
     0 1 0 0
     0 0 1 0
     0 0 0 1])
  (var upsert-a 0)
  (var transform-a 0)
  (local batcher-a {:upsert-text (fn [_self _key _payload]
                                   (set upsert-a (+ upsert-a 1)))
                    :update-text-transform (fn [_self _key _payload]
                                             (set transform-a (+ transform-a 1)))
                    :remove-text (fn [_self _key] nil)})
  (widget:emit-ssbo batcher-a clip-matrix)
  (widget:set-local-position 0.2 0.1 0 0)
  (NextLayout.run-frame widget 10 10 0)
  (widget:emit-ssbo batcher-a clip-matrix)
  (assert (= upsert-a 1))
  (assert (= transform-a 1))

  (var upsert-b 0)
  (var transform-b 0)
  (local batcher-b {:upsert-text (fn [_self _key _payload]
                                   (set upsert-b (+ upsert-b 1)))
                    :update-text-transform (fn [_self _key _payload]
                                             (set transform-b (+ transform-b 1)))
                    :remove-text (fn [_self _key] nil)})
  (widget:emit-ssbo batcher-b clip-matrix)
  (assert (= upsert-b 1))
  (assert (= transform-b 0)))

(table.insert tests {:name "NextApp TextWidget measures and emits codepoints"
                     :fn next-app-text-widget-measures-and-emits-codepoints})
(table.insert tests {:name "NextApp TextWidget set-text marks measure dirty"
                     :fn next-app-text-widget-set-text-marks-measure-dirty})
(table.insert tests {:name "NextApp TextWidget measure cache invalidates on text change"
                     :fn next-app-text-widget-measure-cache-invalidates-on-text-change})
(table.insert tests {:name "NextApp TextWidget uses transform-only updates when content is clean"
                     :fn next-app-text-widget-uses-transform-only-updates-when-content-is-clean})
(table.insert tests {:name "NextApp TextWidget re-upserts on batcher swap"
                     :fn next-app-text-widget-reupserts-when-batcher-instance-changes})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-app-text-widget"
                       :tests tests})))

{:name "next-app-text-widget"
 :tests tests
 :main main}

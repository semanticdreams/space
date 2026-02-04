(local glm (require :glm))
(local _ (require :main))
(local QrCode (require :qr-code))
(local {: QrCodeWidget} (require :qr-code-widget))

(local tests [])

(fn make-vector-buffer []
    (local state {:allocate 0
                  :delete 0
                  :vec3-writes 0
                  :vec4-writes 0
                  :float-writes 0})
    (local buffer {:state state})
    (set buffer.allocate (fn [_self _count]
                           (set state.allocate (+ state.allocate 1))
                           state.allocate))
    (set buffer.delete (fn [_self _handle]
                         (set state.delete (+ state.delete 1))))
    (set buffer.set-glm-vec3 (fn [_self _handle _offset _value]
                               (set state.vec3-writes (+ state.vec3-writes 1))))
    (set buffer.set-glm-vec4 (fn [_self _handle _offset _value]
                               (set state.vec4-writes (+ state.vec4-writes 1))))
    (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
    (set buffer.set-float (fn [_self _handle _offset _value]
                            (set state.float-writes (+ state.float-writes 1))))
    buffer)

(fn make-test-ctx []
    {:triangle-vector (make-vector-buffer)})

(fn count-dark [qr]
    (var total 0)
    (local size (. qr :size))
    (for [y 0 (- size 1)]
        (for [x 0 (- size 1)]
            (when (qr:get x y)
                (set total (+ total 1)))))
    total)

(fn assert-finder [qr x y]
    (for [dy 0 6]
        (for [dx 0 6]
            (local expected
                (or (= dx 0) (= dx 6) (= dy 0) (= dy 6)
                    (and (>= dx 2) (<= dx 4) (>= dy 2) (<= dy 4))))
            (assert (= (qr:get (+ x dx) (+ y dy)) expected)
                    "Finder pattern mismatch")))
    (for [i 0 7]
        (assert (= (qr:get (+ x 7) (+ y i)) false) "Finder separator mismatch")
        (assert (= (qr:get (+ x i) (+ y 7)) false) "Finder separator mismatch")))

(fn qr-code-basic-patterns []
    (local qr (QrCode.encode "A"))
    (assert (= (. qr :size) 21) "QrCode should choose version 1 for short input")
    (assert-finder qr 0 0)
    (local dark-x 8)
    (local dark-y (- (. qr :size) 8))
    (assert (qr:get dark-x dark-y) "QrCode should set dark module"))

(fn qr-code-version-upgrade []
    (local qr (QrCode.encode (string.rep "A" 50)))
    (assert (> (. qr :size) 21) "QrCode should pick larger versions for longer input"))

(fn qr-code-widget-renders []
    (local ctx (make-test-ctx))
    (local qr (QrCode.encode "A"))
    (local dark-count (count-dark qr))
    (local widget ((QrCodeWidget {:value "A"
                                  :module-size 1
                                  :quiet-zone 2})
                   ctx))
    (widget.layout:measurer)
    (local expected-size (+ (. qr :size) 4))
    (assert (= widget.layout.measure.x expected-size))
    (assert (= widget.layout.measure.y expected-size))
    (set widget.layout.size (glm.vec3 expected-size expected-size 0))
    (set widget.layout.position (glm.vec3 0 0 0))
    (set widget.layout.rotation (glm.quat 1 0 0 0))
    (widget.layout:layouter)
    (local writes (+ (* dark-count 6) 6))
    (assert (= ctx.triangle-vector.state.vec3-writes writes) "QrCodeWidget should render all modules")
    (assert (= ctx.triangle-vector.state.vec4-writes writes) "QrCodeWidget should set colors")
    (assert (= ctx.triangle-vector.state.float-writes writes) "QrCodeWidget should set depth")
    (widget:drop))

(table.insert tests {:name "QrCode basic patterns" :fn qr-code-basic-patterns})
(table.insert tests {:name "QrCode version upgrade" :fn qr-code-version-upgrade})
(table.insert tests {:name "QrCode widget renders" :fn qr-code-widget-renders})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "qr-code"
                           :tests tests})))

{:name "qr-code"
 :tests tests
 :main main}

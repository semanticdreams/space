(local math math)

(local ECC_LEVELS {:low 1
                   :medium 2
                   :quartile 3
                   :high 4
                   :l 1
                   :m 2
                   :q 3
                   :h 4
                   "low" 1
                   "medium" 2
                   "quartile" 3
                   "high" 4
                   "l" 1
                   "m" 2
                   "q" 3
                   "h" 4})

(local ECC_FORMAT_BITS [1 0 3 2])
;; QR mode indicators
(local MODE_NUMERIC 1)
(local MODE_ALPHANUMERIC 2)
(local MODE_BYTE 4)

(local ALPHANUMERIC_CHARSET "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:")

(local ECC_CODEWORDS_PER_BLOCK
       [[7 10 13 17]
        [10 16 22 28]
        [15 26 36 44]
        [20 36 52 64]
        [26 48 72 88]
        [36 64 96 112]
        [40 72 108 130]
        [48 88 132 156]
        [60 110 160 192]
        [72 130 192 224]
        [80 150 224 264]
        [96 176 260 308]
        [104 198 288 352]
        [120 216 320 384]
        [132 240 360 432]
        [144 280 408 480]
        [168 308 448 532]
        [180 338 504 588]
        [196 364 546 650]
        [224 416 600 700]
        [224 442 644 750]
        [252 476 690 816]
        [270 504 750 900]
        [300 560 810 960]
        [312 588 870 1050]
        [336 644 952 1110]
        [360 700 1020 1200]
        [390 728 1050 1260]
        [420 784 1140 1350]
        [450 812 1200 1440]
        [480 868 1290 1530]
        [510 924 1350 1620]
        [540 980 1440 1710]
        [570 1036 1530 1800]
        [570 1064 1590 1890]
        [600 1120 1680 1980]
        [630 1204 1770 2100]
        [660 1260 1860 2220]
        [720 1316 1950 2310]
        [750 1372 2040 2430]])

(local NUM_ERROR_CORRECTION_BLOCKS
       [[1 1 1 1]
        [1 1 1 1]
        [1 1 2 2]
        [1 2 2 4]
        [1 2 4 4]
        [2 4 4 4]
        [2 4 6 5]
        [2 4 6 6]
        [2 5 8 8]
        [4 5 8 8]
        [4 5 8 11]
        [4 8 10 11]
        [4 9 12 16]
        [4 9 16 16]
        [6 10 12 18]
        [6 10 17 16]
        [6 11 16 19]
        [6 13 18 21]
        [7 14 21 25]
        [8 16 20 25]
        [8 17 23 25]
        [9 17 23 34]
        [9 18 25 30]
        [10 20 27 32]
        [12 21 29 35]
        [12 23 34 37]
        [12 25 34 40]
        [13 26 35 42]
        [14 28 38 45]
        [15 29 40 48]
        [16 31 43 51]
        [17 33 45 54]
        [18 35 48 57]
        [19 37 51 60]
        [19 38 53 63]
        [20 40 56 66]
        [21 43 59 70]
        [22 45 62 74]
        [24 47 65 77]
        [25 49 68 81]])

(fn resolve-ecc [value]
    (local chosen (or value :medium))
    (local key (if (= (type chosen) :string) (string.lower chosen) chosen))
    (local index (. ECC_LEVELS key))
    (assert index (.. "QrCode unknown ecc level " (tostring chosen)))
    index)

(fn bit-xor [a b]
    (var result 0)
    (var bit 1)
    (var x a)
    (var y b)
    (while (or (> x 0) (> y 0))
        (local abit (% x 2))
        (local bbit (% y 2))
        (when (not (= abit bbit))
            (set result (+ result bit)))
        (set x (math.floor (/ x 2)))
        (set y (math.floor (/ y 2)))
        (set bit (* bit 2)))
    result)

(fn bit-and [a b]
    (var result 0)
    (var bit 1)
    (var x a)
    (var y b)
    (while (and (> x 0) (> y 0))
        (when (and (= (% x 2) 1) (= (% y 2) 1))
            (set result (+ result bit)))
        (set x (math.floor (/ x 2)))
        (set y (math.floor (/ y 2)))
        (set bit (* bit 2)))
    result)

(fn bit-or [a b]
    (var result 0)
    (var bit 1)
    (var x a)
    (var y b)
    (while (or (> x 0) (> y 0))
        (when (or (= (% x 2) 1) (= (% y 2) 1))
            (set result (+ result bit)))
        (set x (math.floor (/ x 2)))
        (set y (math.floor (/ y 2)))
        (set bit (* bit 2)))
    result)

(fn bit-lshift [value shift]
    (math.floor (* value (^ 2 shift))))

(fn bit-rshift [value shift]
    (math.floor (/ value (^ 2 shift))))

(fn append-bits [buffer value bit-count]
    (for [i (- bit-count 1) 0 -1]
        (local bit (bit-and (bit-rshift value i) 1))
        (table.insert buffer bit)))

(fn reed-solomon-multiply [x y]
    (var z 0)
    (var a x)
    (var b y)
    (for [_ 1 8]
        (when (= (bit-and b 1) 1)
            (set z (bit-xor z a)))
        (set b (bit-rshift b 1))
        (local hi (bit-and a 0x80))
        (set a (bit-lshift a 1))
        (when (= hi 0x80)
            (set a (bit-xor a 0x11d))))
    z)

(fn poly-multiply [p q]
    (local result-length (+ (# p) (# q) -1))
    (local result [])
    (for [_ 1 result-length]
        (table.insert result 0))
    (for [i 1 (# p)]
        (for [j 1 (# q)]
            (local index (+ i j -1))
            (local value (reed-solomon-multiply (. p i) (. q j)))
            (set (. result index) (bit-xor (. result index) value))))
    result)

(fn reed-solomon-divisor [degree]
    (var result [1])
    (for [i 0 (- degree 1)]
        (local term [1])
        (var root 1)
        (for [_ 1 i]
            (set root (reed-solomon-multiply root 2)))
        (table.insert term root)
        (set result (poly-multiply result term)))
    (table.remove result 1)
    result)

(fn reed-solomon-remainder [data divisor]
    (local result [])
    (for [_ 1 (# divisor)]
        (table.insert result 0))
    (each [_ byte (ipairs data)]
        (local factor (bit-xor byte (. result 1)))
        (table.remove result 1)
        (table.insert result 0)
        (for [i 1 (# divisor)]
            (local value (reed-solomon-multiply (. divisor i) factor))
            (set (. result i) (bit-xor (. result i) value))))
    result)

(fn get-num-raw-data-modules [version]
    (var num (+ (* 16 version version) (* 128 version) 64))
    (when (>= version 2)
        (local num-align (+ (math.floor (/ version 7)) 2))
        (set num (- num (* 25 (- num-align 1) (- num-align 1))))
        (set num (- num (* 2 20 (- num-align 2)))))
    (when (>= version 7)
        (set num (- num 36)))
    num)

(fn get-ecc-codewords-per-block [version ecc]
    (local total-ecc (. (. ECC_CODEWORDS_PER_BLOCK version) ecc))
    (local blocks (. (. NUM_ERROR_CORRECTION_BLOCKS version) ecc))
    (math.floor (/ total-ecc blocks)))

(fn get-num-blocks [version ecc]
    (. (. NUM_ERROR_CORRECTION_BLOCKS version) ecc))

(fn get-data-capacity [version ecc]
    (local total-codewords (math.floor (/ (get-num-raw-data-modules version) 8)))
    (local total-ecc (. (. ECC_CODEWORDS_PER_BLOCK version) ecc))
    (- total-codewords total-ecc))

(fn get-char-count-bits [version]
    (if (<= version 9)
        {:numeric 10 :alphanumeric 9 :byte 8}
        (if (<= version 26)
            {:numeric 12 :alphanumeric 11 :byte 16}
            {:numeric 14 :alphanumeric 13 :byte 16})))

(fn make-alphanumeric-map []
    (local map {})
    (for [i 1 (# ALPHANUMERIC_CHARSET)]
        (set (. map (string.byte ALPHANUMERIC_CHARSET i)) (- i 1)))
    map)

(local ALPHANUMERIC_MAP (make-alphanumeric-map))

(fn is-digit-byte [b]
    (and (>= b 48) (<= b 57)))

(fn is-alphanumeric-byte [b]
    (not (= (. ALPHANUMERIC_MAP b) nil)))

(fn mode-key [mode]
    (if (= mode MODE_NUMERIC)
        :numeric
        (if (= mode MODE_ALPHANUMERIC)
            :alphanumeric
            :byte)))

(fn data-bits-for-length [mode count]
    (if (= mode MODE_NUMERIC)
        (+ (* (math.floor (/ count 3)) 10)
           (if (= (% count 3) 0) 0
               (= (% count 3) 1) 4
               7))
        (if (= mode MODE_ALPHANUMERIC)
            (+ (* (math.floor (/ count 2)) 11)
               (if (= (% count 2) 0) 0 6))
            (* count 8))))

(fn optimize-segments [value version]
    (local value-length (# value))
    (local ccbits (get-char-count-bits version))
    (local max-counts
           {:numeric (- (^ 2 ccbits.numeric) 1)
            :alphanumeric (- (^ 2 ccbits.alphanumeric) 1)
            :byte (- (^ 2 ccbits.byte) 1)})
    (local inf 1000000000)
    (local dp [])
    (local prev [])
    (for [_ 1 (+ value-length 2)]
        (table.insert dp inf)
        (table.insert prev nil))
    (set (. dp 1) 0)
    (for [start 1 value-length]
        (local base-bits (. dp start))
        (when (< base-bits inf)
            (each [_ mode (ipairs [MODE_NUMERIC MODE_ALPHANUMERIC MODE_BYTE])]
                (local key (mode-key mode))
                (local limit (. max-counts key))
                (var run 0)
                (for [idx start value-length]
                    (local byte (string.byte value idx))
                    (local valid?
                           (if (= mode MODE_NUMERIC)
                               (is-digit-byte byte)
                               (if (= mode MODE_ALPHANUMERIC)
                                   (is-alphanumeric-byte byte)
                                   true)))
                    (if (or (not valid?) (>= run limit))
                        (lua "break")
                        (do
                            (set run (+ run 1))
                            (local payload-bits (data-bits-for-length mode run))
                            (local candidate (+ base-bits
                                                4
                                                (. ccbits key)
                                                payload-bits))
                            (local next-index (+ idx 1))
                            (when (< candidate (. dp next-index))
                                (set (. dp next-index) candidate)
                                (set (. prev next-index)
                                     {:start start
                                      :mode mode
                                      :len run}))))))))
    (local end-index (+ value-length 1))
    (assert (< (. dp end-index) inf) "QrCode failed to optimize segments")
    (local segments [])
    (var cursor end-index)
    (while (> cursor 1)
        (local step (. prev cursor))
        (assert step "QrCode segment backtracking failed")
        (table.insert segments 1 step)
        (set cursor step.start))
    {:segments segments
     :bits (. dp end-index)})

(fn append-mode-data [bits value segment]
    (local start segment.start)
    (local len segment.len)
    (local mode segment.mode)
    (if (= mode MODE_NUMERIC)
        (do
            (var idx start)
            (while (<= idx (+ start len -1))
                (local remain (+ start len (- idx)))
                (if (>= remain 3)
                    (do
                        (local d1 (- (string.byte value idx) 48))
                        (local d2 (- (string.byte value (+ idx 1)) 48))
                        (local d3 (- (string.byte value (+ idx 2)) 48))
                        (append-bits bits (+ (* d1 100) (* d2 10) d3) 10)
                        (set idx (+ idx 3)))
                    (if (= remain 2)
                        (do
                            (local d1 (- (string.byte value idx) 48))
                            (local d2 (- (string.byte value (+ idx 1)) 48))
                            (append-bits bits (+ (* d1 10) d2) 7)
                            (set idx (+ idx 2)))
                        (do
                            (local d (- (string.byte value idx) 48))
                            (append-bits bits d 4)
                            (set idx (+ idx 1)))))))
        (if (= mode MODE_ALPHANUMERIC)
            (do
                (var idx start)
                (while (<= idx (+ start len -1))
                    (local remain (+ start len (- idx)))
                    (if (>= remain 2)
                        (do
                            (local a (. ALPHANUMERIC_MAP (string.byte value idx)))
                            (local b (. ALPHANUMERIC_MAP (string.byte value (+ idx 1))))
                            (append-bits bits (+ (* a 45) b) 11)
                            (set idx (+ idx 2)))
                        (do
                            (local a (. ALPHANUMERIC_MAP (string.byte value idx)))
                            (append-bits bits a 6)
                            (set idx (+ idx 1))))))
            (for [idx start (+ start len -1)]
                (append-bits bits (string.byte value idx) 8)))))

(fn encode-segments-bits [value segments version]
    (local ccbits (get-char-count-bits version))
    (local bits [])
    (each [_ segment (ipairs segments)]
        (append-bits bits segment.mode 4)
        (local key (mode-key segment.mode))
        (append-bits bits segment.len (. ccbits key))
        (append-mode-data bits value segment))
    bits)

(fn make-blank-matrix [size]
    (local rows [])
    (for [_ 1 size]
        (local row [])
        (for [_ 1 size]
            (table.insert row nil))
        (table.insert rows row))
    rows)

(fn set-module [modules is-function x y value]
    (local row (. modules (+ y 1)))
    (local function-row (. is-function (+ y 1)))
    (set (. row (+ x 1)) value)
    (set (. function-row (+ x 1)) true))

(fn get-module [modules x y]
    (. (. modules (+ y 1)) (+ x 1)))

(fn draw-finder [modules is-function x y]
    (for [dy -1 7]
        (for [dx -1 7]
            (local xx (+ x dx))
            (local yy (+ y dy))
            (when (and (>= xx 0) (>= yy 0)
                       (< xx (# modules)) (< yy (# modules)))
                (local in-border (or (= dx -1) (= dx 7) (= dy -1) (= dy 7)))
                (local in-square (and (>= dx 0) (<= dx 6) (>= dy 0) (<= dy 6)))
                (local inner (and (>= dx 2) (<= dx 4) (>= dy 2) (<= dy 4)))
                (local on-edge (or (= dx 0) (= dx 6) (= dy 0) (= dy 6)))
                (local black? (and in-square (or on-edge inner)))
                (if in-border
                    (set-module modules is-function xx yy false)
                    (set-module modules is-function xx yy black?))))))

(fn draw-alignment [modules is-function x y]
    (for [dy -2 2]
        (for [dx -2 2]
            (local xx (+ x dx))
            (local yy (+ y dy))
            (local dist (math.max (math.abs dx) (math.abs dy)))
            (set-module modules is-function xx yy (or (= dist 2) (= dist 0))))))

(fn alignment-pattern-positions [version]
    (if (= version 1)
        []
        (do
            (local size (+ (* version 4) 17))
            (local num-align (+ (math.floor (/ version 7)) 2))
            (local step (if (= version 32)
                            26
                            (* 2 (math.floor (/ (+ (* version 4) (* num-align 2) 1)
                                                (* 2 (- num-align 1)))))))
            (local result [6])
            (for [i 1 (- num-align 2)]
                (table.insert result (- size 7 (* (- num-align 1 i) step))))
            (table.insert result (- size 7))
            result)))

(fn draw-timing [modules is-function]
    (local size (# modules))
    (for [i 0 (- size 1)]
        (local bit (= (% i 2) 0))
        (when (= (get-module modules i 6) nil)
            (set-module modules is-function i 6 bit))
        (when (= (get-module modules 6 i) nil)
            (set-module modules is-function 6 i bit))))

(fn draw-format-bits [modules is-function ecc mask]
    (local size (# modules))
    (local data (bit-or (bit-lshift (. ECC_FORMAT_BITS ecc) 3) mask))
    (var rem (bit-lshift data 10))
    (for [i 0 4]
        (when (= (bit-and (bit-rshift rem (+ i 10)) 1) 1)
            (set rem (bit-xor rem (bit-lshift 0x537 i)))))
    (local bits (bit-xor (bit-or (bit-lshift data 10) rem) 0x5412))
    (for [i 0 14]
        (local bit (= (bit-and (bit-rshift bits i) 1) 1))
        (if (< i 6)
            (set-module modules is-function 8 i bit)
            (if (= i 6)
                (set-module modules is-function 8 7 bit)
                (if (= i 7)
                    (set-module modules is-function 8 8 bit)
                    (if (= i 8)
                        (set-module modules is-function 7 8 bit)
                        (set-module modules is-function (- 14 i) 8 bit)))))
        (if (< i 8)
            (set-module modules is-function (- size 1 i) 8 bit)
            (set-module modules is-function 8 (+ (- size 15) i) bit))))

(fn draw-version-bits [modules is-function version]
    (local size (# modules))
    (when (>= version 7)
        (var rem (bit-lshift version 12))
        (for [i 0 5]
            (when (= (bit-and (bit-rshift rem (+ i 12)) 1) 1)
                (set rem (bit-xor rem (bit-lshift 0x1f25 i)))))
        (local bits (bit-or (bit-lshift version 12) rem))
        (for [i 0 17]
            (local bit (= (bit-and (bit-rshift bits i) 1) 1))
            (local a (+ (- size 11) (% i 3)))
            (local b (math.floor (/ i 3)))
            (set-module modules is-function a b bit)
            (set-module modules is-function b a bit))))

(fn apply-mask [modules is-function mask]
    (local size (# modules))
    (for [y 0 (- size 1)]
        (for [x 0 (- size 1)]
            (when (not (. (. is-function (+ y 1)) (+ x 1)))
                (local prod (* x y))
                (local invert?
                    (if (= mask 0) (= (% (+ x y) 2) 0)
                        (= mask 1) (= (% y 2) 0)
                        (= mask 2) (= (% x 3) 0)
                        (= mask 3) (= (% (+ x y) 3) 0)
                        (= mask 4) (= (% (+ (math.floor (/ x 3)) (math.floor (/ y 2))) 2) 0)
                        (= mask 5) (= (+ (% prod 2) (% prod 3)) 0)
                        (= mask 6) (= (% (+ (% prod 2) (% prod 3)) 2) 0)
                        (= mask 7) (= (% (+ (% (+ x y) 2) (% prod 3)) 2) 0)
                        false))
                (when invert?
                    (local current (get-module modules x y))
                    (local row (. modules (+ y 1)))
                    (set (. row (+ x 1)) (not current)))))))

(fn penalty-n1 [modules]
    (local size (# modules))
    (var penalty 0)
    (for [y 0 (- size 1)]
        (var run-color nil)
        (var run-length 0)
        (for [x 0 (- size 1)]
            (local color (get-module modules x y))
            (if (= color run-color)
                (set run-length (+ run-length 1))
                (do
                    (when (>= run-length 5)
                        (set penalty (+ penalty (- run-length 2))))
                    (set run-color color)
                    (set run-length 1)))
            (when (= x (- size 1))
                (when (>= run-length 5)
                    (set penalty (+ penalty (- run-length 2)))))))
    (for [x 0 (- size 1)]
        (var run-color nil)
        (var run-length 0)
        (for [y 0 (- size 1)]
            (local color (get-module modules x y))
            (if (= color run-color)
                (set run-length (+ run-length 1))
                (do
                    (when (>= run-length 5)
                        (set penalty (+ penalty (- run-length 2))))
                    (set run-color color)
                    (set run-length 1)))
            (when (= y (- size 1))
                (when (>= run-length 5)
                    (set penalty (+ penalty (- run-length 2)))))))
    penalty)

(fn penalty-n2 [modules]
    (local size (# modules))
    (var penalty 0)
    (for [y 0 (- size 2)]
        (for [x 0 (- size 2)]
            (local c (get-module modules x y))
            (when (and (= c (get-module modules (+ x 1) y))
                       (= c (get-module modules x (+ y 1)))
                       (= c (get-module modules (+ x 1) (+ y 1))))
                (set penalty (+ penalty 3)))))
    penalty)

(fn penalty-n3 [modules]
    (local size (# modules))
    (var penalty 0)
    (local pattern [true false true true true false true])
    (fn line-at [line index]
        (. line (+ index 1)))
    (fn matches-pattern [line index]
        (var ok true)
        (for [i 0 6]
            (when (not (= (line-at line (+ index i)) (. pattern (+ i 1))))
                (set ok false)))
        ok)
    (for [y 0 (- size 1)]
        (local line [])
        (for [x 0 (- size 1)]
            (table.insert line (get-module modules x y)))
        (for [x 0 (- size 7)]
            (when (matches-pattern line x)
                (local left-clear (and (>= x 4)
                                       (not (line-at line (- x 4)))
                                       (not (line-at line (- x 3)))
                                       (not (line-at line (- x 2)))
                                       (not (line-at line (- x 1)))))
                (local right-clear (and (<= (+ x 10) (- size 1))
                                        (not (line-at line (+ x 7)))
                                        (not (line-at line (+ x 8)))
                                        (not (line-at line (+ x 9)))
                                        (not (line-at line (+ x 10)))))
                (when (or left-clear right-clear)
                    (set penalty (+ penalty 40))))))
    (for [x 0 (- size 1)]
        (local line [])
        (for [y 0 (- size 1)]
            (table.insert line (get-module modules x y)))
        (for [y 0 (- size 7)]
            (when (matches-pattern line y)
                (local top-clear (and (>= y 4)
                                      (not (line-at line (- y 4)))
                                      (not (line-at line (- y 3)))
                                      (not (line-at line (- y 2)))
                                      (not (line-at line (- y 1)))))
                (local bottom-clear (and (<= (+ y 10) (- size 1))
                                         (not (line-at line (+ y 7)))
                                         (not (line-at line (+ y 8)))
                                         (not (line-at line (+ y 9)))
                                         (not (line-at line (+ y 10)))))
                (when (or top-clear bottom-clear)
                    (set penalty (+ penalty 40))))))
    penalty)

(fn penalty-n4 [modules]
    (local size (# modules))
    (var dark 0)
    (for [y 0 (- size 1)]
        (for [x 0 (- size 1)]
            (when (get-module modules x y)
                (set dark (+ dark 1)))))
    (local total (* size size))
    (local k (math.floor (/ (math.abs (- (* dark 20) (* total 10))) total)))
    (* k 10))

(fn calculate-penalty [modules]
    (+ (penalty-n1 modules)
       (penalty-n2 modules)
       (penalty-n3 modules)
       (penalty-n4 modules)))

(fn draw-function-patterns [modules is-function version]
    (local size (# modules))
    (draw-finder modules is-function 0 0)
    (draw-finder modules is-function (- size 7) 0)
    (draw-finder modules is-function 0 (- size 7))
    (draw-timing modules is-function)
    (each [_ x (ipairs (alignment-pattern-positions version))]
        (each [_ y (ipairs (alignment-pattern-positions version))]
            (when (not (or (and (= x 6) (= y 6))
                           (and (= x 6) (= y (- size 7)))
                           (and (= x (- size 7)) (= y 6))))
                (when (= (get-module modules x y) nil)
                    (draw-alignment modules is-function x y)))))
    (set-module modules is-function 8 (- size 8) true)
    (draw-version-bits modules is-function version))

(fn place-data-bits [modules is-function bits]
    (local size (# modules))
    (var i 1)
    (var upward true)
    (var x (- size 1))
    (fn next-bit []
        (local bit (if (<= i (# bits)) (= (. bits i) 1) false))
        (set i (+ i 1))
        bit)
    (fn place-at [xx yy]
        (when (not (. (. is-function (+ yy 1)) (+ xx 1)))
            (local row (. modules (+ yy 1)))
            (set (. row (+ xx 1)) (next-bit))))
    (while (> x 0)
        (when (= x 6)
            (set x (- x 1)))
        (for [offset 0 (- size 1)]
            (local yy (if upward (- size 1 offset) offset))
            (place-at x yy)
            (place-at (- x 1) yy))
        (set upward (not upward))
        (set x (- x 2))))

(fn encode-codewords [payload-bits version ecc]
    (local data-capacity (get-data-capacity version ecc))
    (local data-bits [])
    (each [_ bit (ipairs payload-bits)]
        (table.insert data-bits bit))
    (local total-bits (* data-capacity 8))
    (local terminator (math.min 4 (- total-bits (# data-bits))))
    (for [_ 1 terminator]
        (table.insert data-bits 0))
    (while (not (= (% (# data-bits) 8) 0))
        (table.insert data-bits 0))
    (local pad-bytes [0xec 0x11])
    (var pad-index 1)
    (while (< (/ (# data-bits) 8) data-capacity)
        (append-bits data-bits (. pad-bytes pad-index) 8)
        (set pad-index (if (= pad-index 1) 2 1)))
    (local data-codewords [])
    (for [i 1 (# data-bits) 8]
        (var value 0)
        (for [j 0 7]
            (set value (+ (* value 2) (. data-bits (+ i j)))))
        (table.insert data-codewords value))
    (local total-codewords (math.floor (/ (get-num-raw-data-modules version) 8)))
    (local num-blocks (get-num-blocks version ecc))
    (local ecc-codewords (get-ecc-codewords-per-block version ecc))
    (local short-block-len (math.floor (/ total-codewords num-blocks)))
    (local num-short-blocks (- num-blocks (% total-codewords num-blocks)))
    (local short-data-len (- short-block-len ecc-codewords))
    (local blocks [])
    (var offset 1)
    (local divisor (reed-solomon-divisor ecc-codewords))
    (for [block 1 num-blocks]
        (local data-len (if (<= block num-short-blocks) short-data-len (+ short-data-len 1)))
        (local block-data [])
        (for [_ 1 data-len]
            (table.insert block-data (. data-codewords offset))
            (set offset (+ offset 1)))
        (local block-ecc (reed-solomon-remainder block-data divisor))
        (local block-full [])
        (each [_ byte (ipairs block-data)]
            (table.insert block-full byte))
        (each [_ byte (ipairs block-ecc)]
            (table.insert block-full byte))
        (table.insert blocks block-full))
    (local interleaved [])
    (var max-block-len 0)
    (each [_ block (ipairs blocks)]
        (set max-block-len (math.max max-block-len (# block))))
    (for [i 1 max-block-len]
        (each [_ block (ipairs blocks)]
            (when (<= i (# block))
                (table.insert interleaved (. block i)))))
    (local final-bits [])
    (each [_ byte (ipairs interleaved)]
        (append-bits final-bits byte 8))
    (local remainder (% (get-num-raw-data-modules version) 8))
    (for [_ 1 remainder]
        (table.insert final-bits 0))
    final-bits)

(fn build-result [size version ecc mask modules]
    {:size size
     :version version
     :ecc ecc
     :mask mask
     :modules modules
     :get (fn [_self x y]
             (assert (and (>= x 0) (>= y 0) (< x size) (< y size))
                     "QrCode.get out of range")
             (get-module modules x y))})

(fn encode [value opts]
    (assert (= (type value) :string) "QrCode.encode requires a string")
    (local options (or opts {}))
    (local ecc (resolve-ecc options.ecc))
    (var version nil)
    (var best-segments nil)
    (for [candidate 1 40]
        (local capacity (* (get-data-capacity candidate ecc) 8))
        (local optimized (optimize-segments value candidate))
        (when (and (not version) (>= capacity optimized.bits))
            (set version candidate)
            (set best-segments optimized.segments)))
    (assert version "QrCode input too long")
    (local size (+ (* version 4) 17))
    (local modules (make-blank-matrix size))
    (local is-function (make-blank-matrix size))
    (draw-function-patterns modules is-function version)
    ;; Reserve format info modules before placing payload bits.
    (draw-format-bits modules is-function ecc 0)
    (assert best-segments "QrCode segment selection failed")
    (local payload-bits (encode-segments-bits value best-segments version))
    (local bits (encode-codewords payload-bits version ecc))
    (place-data-bits modules is-function bits)
    (var best-mask nil)
    (var best-penalty nil)
    (var best-modules nil)
    (for [mask 0 7]
        (local masked (make-blank-matrix size))
        (for [y 0 (- size 1)]
            (for [x 0 (- size 1)]
                (local row (. masked (+ y 1)))
                (set (. row (+ x 1)) (get-module modules x y))))
        (apply-mask masked is-function mask)
        (draw-format-bits masked is-function ecc mask)
        (local penalty (calculate-penalty masked))
        (when (or (not best-penalty) (< penalty best-penalty))
            (set best-mask mask)
            (set best-penalty penalty)
            (set best-modules masked)))
    (draw-format-bits best-modules is-function ecc best-mask)
    (build-result size version ecc best-mask best-modules))

{:encode encode}

(local math math)

(local base64-alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(fn trim-leading-zeros [value]
    (local trimmed (string.gsub value "^0+" ""))
    (if (= trimmed "") "0" trimmed))

(fn normalize-decimal [value]
    (var trimmed (string.gsub value "^%s+" ""))
    (set trimmed (string.gsub trimmed "%s+$" ""))
    (assert (not (= trimmed "")) "decimal value required")
    (assert (string.match trimmed "^%d+$") "decimal value must be digits")
    (trim-leading-zeros trimmed))

(fn decimal-divide [value divisor]
    (var remainder 0)
    (var out "")
    (for [i 1 (# value)]
        (local digit (- (string.byte value i) 48))
        (local acc (+ (* remainder 10) digit))
        (local q (math.floor (/ acc divisor)))
        (set remainder (- acc (* q divisor)))
        (when (or (not (= out "")) (not (= q 0)))
            (set out (.. out (tostring q)))))
    (values (if (= out "") "0" out) remainder))

(fn decimal-to-bytes [value]
    (local normalized (normalize-decimal value))
    (if (= normalized "0")
        []
        (do
            (var bytes [])
            (var current normalized)
            (while (not (= current "0"))
                (local (next remainder) (decimal-divide current 256))
                (table.insert bytes remainder)
                (set current next))
            (local output [])
            (for [i (# bytes) 1 -1]
                (table.insert output (. bytes i)))
            output)))

(fn hex-digit-value [char]
    (local byte (string.byte char))
    (if (and (>= byte 48) (<= byte 57))
        (- byte 48)
        (if (and (>= byte 65) (<= byte 70))
            (+ 10 (- byte 65))
            (if (and (>= byte 97) (<= byte 102))
                (+ 10 (- byte 97))
                (error (.. "Invalid hex digit " char))))))

(fn hex-to-bytes [value]
    (assert (= (type value) :string) "hex value must be a string")
    (var trimmed (string.gsub value "^0x" ""))
    (set trimmed (string.gsub trimmed "^0+" ""))
    (when (= trimmed "")
        (lua "return {}"))
    (when (= (% (# trimmed) 2) 1)
        (set trimmed (.. "0" trimmed)))
    (local bytes [])
    (for [i 1 (# trimmed) 2]
        (local hi (hex-digit-value (string.sub trimmed i i)))
        (local lo (hex-digit-value (string.sub trimmed (+ i 1) (+ i 1))))
        (table.insert bytes (+ (* hi 16) lo)))
    bytes)

(fn bytes-to-base64 [bytes]
    (local count (# bytes))
    (if (= count 0)
        ""
        (do
            (var out "")
            (var i 1)
            (fn append [value]
                (set out (.. out value)))
            (while (<= i count)
                (local b1 (or (. bytes i) 0))
                (local b2 (or (. bytes (+ i 1)) 0))
                (local b3 (or (. bytes (+ i 2)) 0))
                (local triple (+ (* b1 65536) (* b2 256) b3))
                (local c1 (+ 1 (math.floor (/ triple 262144))))
                (local c2 (+ 1 (% (math.floor (/ triple 4096)) 64)))
                (local c3 (+ 1 (% (math.floor (/ triple 64)) 64)))
                (local c4 (+ 1 (% triple 64)))
                (append (string.sub base64-alphabet c1 c1))
                (append (string.sub base64-alphabet c2 c2))
                (if (> (+ i 1) count)
                    (append "==")
                    (do
                        (append (string.sub base64-alphabet c3 c3))
                        (if (> (+ i 2) count)
                            (append "=")
                            (append (string.sub base64-alphabet c4 c4)))))
                (set i (+ i 3)))
            out)))

(fn hex-to-base64 [value]
    (bytes-to-base64 (hex-to-bytes value)))

(fn decimal-to-base64 [value]
    (bytes-to-base64 (decimal-to-bytes value)))

(fn decimal-to-hex [value]
    (local normalized (normalize-decimal value))
    (if (= normalized "0")
        "0x0"
        (do
            (local digits "0123456789abcdef")
            (var current normalized)
            (var out "")
            (while (not (= current "0"))
                (local (next remainder) (decimal-divide current 16))
                (local index (+ remainder 1))
                (set out (.. (string.sub digits index index) out))
                (set current next))
            (.. "0x" out))))

(fn hex-to-decimal [hex]
    (assert hex "hex-to-decimal requires a value")
    (var trimmed (string.gsub (string.lower hex) "^0x" ""))
    (when (= trimmed "")
        (set trimmed "0"))
    (var digits [0])
    (for [i 1 (# trimmed)]
        (local value (hex-digit-value (string.sub trimmed i i)))
        (var carry value)
        (for [j 1 (# digits)]
            (local total (+ (* (. digits j) 16) carry))
            (set (. digits j) (% total 10))
            (set carry (math.floor (/ total 10))))
        (while (> carry 0)
            (table.insert digits (% carry 10))
            (set carry (math.floor (/ carry 10)))))
    (var out "")
    (for [i (# digits) 1 -1]
        (set out (.. out (tostring (. digits i)))))
    out)

(fn format-eth [decimal]
    (var cleaned (string.gsub decimal "^0+" ""))
    (when (= cleaned "")
        (set cleaned "0"))
    (local precision 18)
    (if (<= (# cleaned) precision)
        (.. "0." (string.rep "0" (- precision (# cleaned))) cleaned)
        (do
            (local split (- (# cleaned) precision))
            (local int-part (string.sub cleaned 1 split))
            (local frac-part (string.sub cleaned (+ split 1)))
            (.. int-part "." frac-part))))

(fn format-balance [hex]
    (local decimal (hex-to-decimal hex))
    (local eth (format-eth decimal))
    (.. hex " (" eth " ETH)"))

(fn eth-to-wei [value]
    (assert (= (type value) :string) "ETH amount must be a string")
    (var trimmed (string.gsub value "^%s+" ""))
    (set trimmed (string.gsub trimmed "%s+$" ""))
    (assert (string.match trimmed "^%d+%.?%d*$") "ETH amount must be numeric")
    (local int-part (string.match trimmed "^%d+"))
    (local frac-part (or (string.match trimmed "^%d+%.(%d+)$") ""))
    (when (> (# frac-part) 18)
        (error "ETH amount supports up to 18 decimal places"))
    (local padded (.. frac-part (string.rep "0" (- 18 (# frac-part)))))
    (local combined (.. int-part padded))
    (trim-leading-zeros combined))

{:decimal-to-bytes decimal-to-bytes
 :decimal-to-base64 decimal-to-base64
 :decimal-to-hex decimal-to-hex
 :hex-to-bytes hex-to-bytes
 :hex-to-base64 hex-to-base64
 :hex-to-decimal hex-to-decimal
 :format-eth format-eth
 :format-balance format-balance
 :eth-to-wei eth-to-wei}

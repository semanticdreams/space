(local json (require :json))

(fn array-length [value]
  (var max-index 0)
  (var count 0)
  (var array? true)
  (each [k _v (pairs value)]
    (if (and (= (type k) "number")
             (= k (math.floor k))
             (> k 0))
        (do
          (set count (+ count 1))
          (set max-index (math.max max-index k)))
        (set array? false)))
  (if (and array? (> count 0) (= count max-index))
      max-index
      nil))

(fn sorted-object-entries [value]
  (local entries [])
  (each [k _v (pairs value)]
    (table.insert entries {:key k :name (tostring k)}))
  (table.sort entries (fn [a b] (< a.name b.name)))
  entries)

(fn canonical [value]
  (local kind (type value))
  (if (= kind "nil")
      "null"
      (= kind "boolean")
      (if value "true" "false")
      (= kind "number")
      (do
        (assert (= value value) "approval fingerprint cannot encode NaN")
        (json.dumps value))
      (= kind "string")
      (json.dumps value)
      (= kind "table")
      (do
        (local n (array-length value))
        (if n
            (do
              (local parts [])
              (for [i 1 n]
                (table.insert parts (canonical (. value i))))
              (.. "[" (table.concat parts ",") "]"))
            (do
              (local parts [])
              (each [_ entry (ipairs (sorted-object-entries value))]
                (table.insert parts (.. (json.dumps entry.name) ":" (canonical (. value entry.key)))))
              (.. "{" (table.concat parts ",") "}"))))
      (error (.. "approval fingerprint unsupported value type: " kind))))

(fn djb2-hash-hex [text]
  (var h 5381)
  (for [i 1 (# text)]
    (set h (% (+ (* h 33) (string.byte text i)) 4294967296)))
  (string.format "%08x" h))

(fn preview [value max-len]
  (local text (canonical value))
  (local limit (or max-len 240))
  (if (> (# text) limit)
      (.. (string.sub text 1 (- limit 3)) "...")
      text))

(fn fingerprint [value]
  (local text (canonical (or value {})))
  {:hash (djb2-hash-hex text)
   :canonical text
   :preview (preview (or value {}) 240)})

{:canonical canonical
 :fingerprint fingerprint
 :preview preview}

(local glm (require :glm))

(local M {})

(fn integer-field [value fallback]
  (local resolved (if (= value nil) fallback value))
  (if (= resolved nil)
      nil
      (math.floor (+ resolved 0.0))))

(fn M.spacing [record]
  (local sample-spacing (or (and record record.options record.options.sample-spacing) [20 20]))
  [(or (. sample-spacing 1) sample-spacing.x 20)
   (or (. sample-spacing 2) sample-spacing.y sample-spacing.z 20)])

(fn M.chunk-samples [record]
  (local samples (or (and record record.options record.options.chunk-samples) [17 17]))
  [(integer-field (or (. samples 1) samples.x 17) 17)
   (integer-field (or (. samples 2) samples.y samples.z 17) 17)])

(fn M.chunk-key [chunk-x chunk-z]
  (.. (integer-field chunk-x 0) ":" (integer-field chunk-z 0)))

(fn chunk-height [chunk sample-x sample-z]
  (local size (or chunk.size [17 17]))
  (local width (integer-field (or (. size 1) size.x 17) 17))
  (local idx (+ (* sample-z width) sample-x 1))
  (or (. chunk.heights idx) 0.0))

(fn M.build-chunk-map [record]
  (local out {})
  (each [_ chunk (ipairs (or record.chunks []))]
    (local coord (or chunk.coord [0 0]))
    (local chunk-x (integer-field (or (. coord 1) coord.x 0) 0))
    (local chunk-z (integer-field (or (. coord 2) coord.y coord.z 0) 0))
    (set (. out (M.chunk-key chunk-x chunk-z)) chunk))
  out)

(fn M.sample-height-global [record chunk-map sample-x sample-z]
  (local sample-counts (M.chunk-samples record))
  (local stride-x (- (. sample-counts 1) 1))
  (local stride-z (- (. sample-counts 2) 1))
  (local primary-chunk-x (math.floor (/ sample-x stride-x)))
  (local primary-chunk-z (math.floor (/ sample-z stride-z)))
  (local primary-local-x (- sample-x (* primary-chunk-x stride-x)))
  (local primary-local-z (- sample-z (* primary-chunk-z stride-z)))

  (fn try-sample [chunk-x chunk-z local-x local-z]
    (local chunk (. chunk-map (M.chunk-key chunk-x chunk-z)))
    (if (and chunk
             (>= local-x 0) (< local-x (. sample-counts 1))
             (>= local-z 0) (< local-z (. sample-counts 2)))
        (chunk-height chunk local-x local-z)
        nil))

  (local primary
    (try-sample primary-chunk-x primary-chunk-z primary-local-x primary-local-z))
  (if (not (= primary nil))
      primary
      (do
        (local seam-x-sample
          (if (= primary-local-x 0)
              (try-sample (- primary-chunk-x 1) primary-chunk-z stride-x primary-local-z)
              nil))
        (if (not (= seam-x-sample nil))
            seam-x-sample
            (do
              (local seam-z-sample
                (if (= primary-local-z 0)
                    (try-sample primary-chunk-x (- primary-chunk-z 1) primary-local-x stride-z)
                    nil))
              (if (not (= seam-z-sample nil))
                  seam-z-sample
                  (if (and (= primary-local-x 0) (= primary-local-z 0))
                      (try-sample (- primary-chunk-x 1) (- primary-chunk-z 1) stride-x stride-z)
                      nil)))))))

(fn M.sample-local-point [record chunk-map sample-x sample-z]
  (local sample-spacing (M.spacing record))
  (local spacing-x (. sample-spacing 1))
  (local spacing-z (. sample-spacing 2))
  (local height (M.sample-height-global record chunk-map sample-x sample-z))
  (if (= height nil)
      nil
      (glm.vec3 (* sample-x spacing-x)
                height
                (* sample-z spacing-z))))

{:integer-field integer-field
 :spacing M.spacing
 :chunk-samples M.chunk-samples
 :chunk-key M.chunk-key
 :build-chunk-map M.build-chunk-map
 :sample-height-global M.sample-height-global
 :sample-local-point M.sample-local-point}

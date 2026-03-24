(local glm (require :glm))

(local EPSILON 1e-6)

(fn intersect-triangle [ray a b c]
  (local edge1 (- b a))
  (local edge2 (- c a))
  (local h (glm.cross ray.direction edge2))
  (local det (glm.dot edge1 h))
  (if (and (> det (- EPSILON)) (< det EPSILON))
      nil
      (do
        (local inv-det (/ 1 det))
        (local s (- ray.origin a))
        (local u (* inv-det (glm.dot s h)))
        (if (or (< u 0.0) (> u 1.0))
            nil
            (do
              (local q (glm.cross s edge1))
              (local v (* inv-det (glm.dot ray.direction q)))
              (if (or (< v 0.0) (> (+ u v) 1.0))
                  nil
                  (do
                    (local t (* inv-det (glm.dot edge2 q)))
                    (if (<= t EPSILON)
                        nil
                        {:distance t
                         :point (+ ray.origin (* ray.direction t))
                         :u u
                         :v v}))))))))

{:intersect-triangle intersect-triangle}

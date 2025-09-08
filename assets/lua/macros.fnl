(fn incf [place & amounts]
  `(set ,place (+ ,place ,(unpack amounts))))

(fn maxf [place other]
  `(when (> ,other ,place) (set ,place ,other)))

(fn minf [place other]
  `(when (< ,other ,place) (set ,place ,other)))

{: incf : maxf : minf}

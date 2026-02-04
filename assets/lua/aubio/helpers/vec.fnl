(local aubio-vec (require :aubio/vec))
(local aubio-utils (require :aubio/utils))

(fn mixdown-equal [matrix]
  (aubio-vec.fmat-mixdown-equal matrix))

(fn mixdown-weighted [matrix weights]
  (aubio-vec.fmat-mixdown-weighted matrix weights))

(fn normalize-peak [buffer target floor]
  (aubio-vec.fvec-normalize-peak buffer target floor)
  buffer)

(fn normalize-rms [buffer target floor]
  (aubio-vec.fvec-normalize-rms buffer target floor)
  buffer)

(fn apply-window [buffer window-type]
  (local window (aubio-utils.window window-type (buffer:length)))
  (buffer:weight window)
  buffer)

{: mixdown-equal
 : mixdown-weighted
 : normalize-peak
 : normalize-rms
 : apply-window}

(local aubio-vec (require :aubio/vec))
(local aubio-temporal (require :aubio/temporal))

(fn new [opts]
  (assert opts "onset.new requires opts")
  (local method (assert (. opts :method) "onset.new requires :method"))
  (local buf (assert (. opts :buf) "onset.new requires :buf"))
  (local hop (assert (. opts :hop) "onset.new requires :hop"))
  (local samplerate (assert (. opts :samplerate) "onset.new requires :samplerate"))
  (local detector (aubio-temporal.Onset method buf hop samplerate))
  (local silence (. opts :silence))
  (when silence
    (detector:set-silence silence))
  (local threshold (. opts :threshold))
  (when threshold
    (detector:set-threshold threshold))
  (local minioi (. opts :minioi))
  (when minioi
    (detector:set-minioi minioi))
  (local delay (. opts :delay))
  (when delay
    (detector:set-delay delay))
  (local compression (. opts :compression))
  (when compression
    (detector:set-compression compression))
  (local awhitening (. opts :awhitening))
  (when awhitening
    (detector:set-awhitening awhitening))
  (local output (aubio-vec.FVec 1))
  (fn snapshot []
    (local value (output:get 0))
    {:onset (> value 0)
     :value value
     :last (detector:get-last)
     :last-s (detector:get-last-s)
     :last-ms (detector:get-last-ms)
     :descriptor (detector:get-descriptor)
     :thresholded (detector:get-thresholded-descriptor)})
  (fn push [_self input]
    (assert input "onset.push requires input")
    (detector:do input output)
    (snapshot))
  (fn result [_self]
    (snapshot))
  {:push push
   :result result
   :detector detector
   :output output
   :buf buf
   :hop hop
   :samplerate samplerate})

{: new}

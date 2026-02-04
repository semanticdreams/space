(local aubio-vec (require :aubio/vec))
(local aubio-temporal (require :aubio/temporal))

(fn new [opts]
  (assert opts "tempo.new requires opts")
  (local method (assert (. opts :method) "tempo.new requires :method"))
  (local buf (assert (. opts :buf) "tempo.new requires :buf"))
  (local hop (assert (. opts :hop) "tempo.new requires :hop"))
  (local samplerate (assert (. opts :samplerate) "tempo.new requires :samplerate"))
  (local detector (aubio-temporal.Tempo method buf hop samplerate))
  (local silence (. opts :silence))
  (when silence
    (detector:set-silence silence))
  (local threshold (. opts :threshold))
  (when threshold
    (detector:set-threshold threshold))
  (local tatum-signature (. opts :tatum-signature))
  (when tatum-signature
    (detector:set-tatum-signature tatum-signature))
  (local delay (. opts :delay))
  (when delay
    (detector:set-delay delay))
  (local output (aubio-vec.FVec 1))
  (fn snapshot []
    (local value (output:get 0))
    {:beat (> value 0)
     :value value
     :last (detector:get-last)
     :last-s (detector:get-last-s)
     :last-ms (detector:get-last-ms)
     :bpm (detector:get-bpm)
     :period (detector:get-period)
     :confidence (detector:get-confidence)
     :tatum (detector:was-tatum)
     :last-tatum (detector:get-last-tatum)})
  (fn push [_self input]
    (assert input "tempo.push requires input")
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

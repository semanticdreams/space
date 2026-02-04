(local aubio-vec (require :aubio/vec))
(local aubio-temporal (require :aubio/temporal))

(fn new [opts]
  (assert opts "pitch.new requires opts")
  (local method (assert (. opts :method) "pitch.new requires :method"))
  (local buf (assert (. opts :buf) "pitch.new requires :buf"))
  (local hop (assert (. opts :hop) "pitch.new requires :hop"))
  (local samplerate (assert (. opts :samplerate) "pitch.new requires :samplerate"))
  (local detector (aubio-temporal.Pitch method buf hop samplerate))
  (local unit (. opts :unit))
  (when unit
    (detector:set-unit unit))
  (local tolerance (. opts :tolerance))
  (when tolerance
    (detector:set-tolerance tolerance))
  (local silence (. opts :silence))
  (when silence
    (detector:set-silence silence))
  (local output (aubio-vec.FVec 1))
  (fn snapshot []
    {:value (output:get 0)
     :confidence (detector:get-confidence)})
  (fn push [_self input]
    (assert input "pitch.push requires input")
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

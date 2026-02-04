(local aubio-vec (require :aubio/vec))
(local aubio-io (require :aubio/io))
(local aubio-utils (require :aubio/utils))

(fn from-source [opts]
  (assert opts "stream.from-source requires opts")
  (local uri (assert (. opts :uri) "stream.from-source requires :uri"))
  (local hop (assert (. opts :hop) "stream.from-source requires :hop"))
  (local samplerate (or (. opts :samplerate) 0))
  (local loop? (or (. opts :loop) false))
  (var buffer (. opts :buffer))
  (if buffer
      (assert (>= (buffer:length) hop) "stream.from-source buffer too small")
      (set buffer (aubio-vec.FVec hop)))
  (local source (aubio-io.Source uri samplerate hop))
  (fn iter []
    (var read (source:do buffer))
    (if (> read 0)
        (values read buffer)
        (if loop?
            (do
              (source:seek 0)
              (set read (source:do buffer))
              (if (> read 0)
                  (values read buffer)
                  nil))
            nil)))
  {:source source
   :buffer buffer
   :iter iter
   :hop hop
   :samplerate (source:samplerate)})

(fn from-audio-input [opts]
  (assert opts "stream.from-audio-input requires opts")
  (local input (assert (. opts :input) "stream.from-audio-input requires :input"))
  (local frames (assert (. opts :frames) "stream.from-audio-input requires :frames"))
  (local gain (. opts :gain))
  (local channels (input:channels))
  (assert (> channels 0) "stream.from-audio-input requires channels > 0")
  (var buffer (. opts :buffer))
  (local needed (* frames channels))
  (if buffer
      (assert (>= (buffer:length) needed) "stream.from-audio-input buffer too small")
      (set buffer (aubio-vec.FVec needed)))
  (fn iter []
    (local read (aubio-utils.audio-input-into-fvec input buffer frames))
    (when (and gain (> read 0))
      (aubio-vec.fvec-mul buffer gain))
    (if (> read 0)
        (values read buffer)
        nil))
  {:input input
   :buffer buffer
   :iter iter
   :frames frames
   :channels channels})

{: from-source
 : from-audio-input}

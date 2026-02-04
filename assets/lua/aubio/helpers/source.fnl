(fn stream [source buffer]
  (assert source "stream requires source")
  (assert buffer "stream requires buffer")
  (fn []
    (var read (source:do buffer))
    (if (> read 0)
        (values read buffer)
        nil)))

(fn loop [source buffer]
  (assert source "loop requires source")
  (assert buffer "loop requires buffer")
  (local buf-length (buffer:length))
  (fn []
    (var read (source:do buffer))
    (if (> read 0)
        (do
          (if (< read buf-length)
              (source:seek 0))
          (values read buffer))
        (do
          (source:seek 0)
          (set read (source:do buffer))
          (if (> read 0)
              (values read buffer)
              nil)))))

{: stream
 : loop}

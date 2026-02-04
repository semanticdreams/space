(local fs (require :fs))
(local gl (require :gl))
(local ImageIO (require :image-io))

(fn env-flag? [name]
  (local value (os.getenv name))
  (and value
       (not (or (= value "0")
                (= (string.lower value) "false")
                (= (string.lower value) "off")))))

(fn env-update-targets []
  (local value (os.getenv "SPACE_SNAPSHOT_UPDATE"))
  (if (not value)
      nil
      value))

(fn update-allowed? [name]
  (local targets (env-update-targets))
  (if (not targets)
      false
      (let [names {}]
        (each [entry (string.gmatch targets "[^,]+")]
          (local trimmed (string.gsub entry "^%s*(.-)%s*$" "%1"))
          (when (> (length trimmed) 0)
            (set (. names trimmed) true)))
        (or (not (= (. names "all") nil))
            (not (= (. names name) nil))))))

(fn require-engine-asset-path []
  (assert (and app app.engine app.engine.get-asset-path)
          "snapshots require app.engine.get-asset-path")
  app.engine.get-asset-path)

(fn snapshot-dir []
  (local get-asset-path (require-engine-asset-path))
  (get-asset-path "lua/tests/data/snapshots"))

(fn snapshot-path [name]
  (fs.join-path (snapshot-dir) (.. name ".png")))

(fn ensure-dir [path]
  (when (and fs fs.create-dirs)
    (fs.create-dirs path)))

(fn capture-bytes [width height]
  (gl.glFinish)
  (local bytes (gl.glReadPixels 0 0 width height gl.GL_RGBA gl.GL_UNSIGNED_BYTE))
  (ImageIO.flip-vertical width height 4 bytes))

(fn max-byte-diff [expected actual]
  (local expected-len (string.len expected))
  (local actual-len (string.len actual))
  (when (not (= expected-len actual-len))
    (error (.. "snapshot byte size mismatch: expected " expected-len " got " actual-len)))
  (var max-diff 0)
  (for [i 1 expected-len]
    (local a (string.byte expected i))
    (local b (string.byte actual i))
    (local diff (math.abs (- a b)))
    (when (> diff max-diff)
      (set max-diff diff)))
  max-diff)

(fn write-output [dir name width height bytes]
  (ensure-dir dir)
  (local path (fs.join-path dir (.. name ".png")))
  (ImageIO.write-png path width height 4 bytes)
  path)

(fn capture-and-compare [opts]
  (local name (assert (. opts :name) "snapshot requires :name"))
  (local width (assert (. opts :width) "snapshot requires :width"))
  (local height (assert (. opts :height) "snapshot requires :height"))
  (local tolerance (or (. opts :tolerance) 0))
  (local golden-path (snapshot-path name))
  (local actual-path (.. golden-path ".actual.png"))
  (local actual-bytes (capture-bytes width height))
  (local output-dir (os.getenv "SPACE_SNAPSHOT_OUTPUT_DIR"))
  (when output-dir
    (write-output output-dir name width height actual-bytes))
  (if (update-allowed? name)
      (do
        (ensure-dir (snapshot-dir))
        (ImageIO.write-png golden-path width height 4 actual-bytes)
        (print (.. "[snapshot] updated " golden-path))
        (when (fs.exists actual-path)
          (fs.remove actual-path))
        true)
      (do
        (when (not (fs.exists golden-path))
          (error (.. "missing snapshot golden: " golden-path
                     " (set SPACE_SNAPSHOT_UPDATE=" name
                     " to create)")))
        (local golden (ImageIO.read-png golden-path))
        (when (not (= golden.width width))
          (error (.. "snapshot width mismatch: " golden.width " != " width)))
        (when (not (= golden.height height))
          (error (.. "snapshot height mismatch: " golden.height " != " height)))
        (when (not (= golden.channels 4))
          (error (.. "snapshot golden is not RGBA: " golden.channels " channels")))
        (local diff (max-byte-diff golden.bytes actual-bytes))
        (when (> diff tolerance)
          (ImageIO.write-png actual-path width height 4 actual-bytes)
          (error (.. "snapshot mismatch: max diff " diff " (see " actual-path ")")))
        (when (fs.exists actual-path)
          (fs.remove actual-path))
        true)))

{:capture-and-compare capture-and-compare
 :snapshot-path snapshot-path
 :snapshot-dir snapshot-dir}

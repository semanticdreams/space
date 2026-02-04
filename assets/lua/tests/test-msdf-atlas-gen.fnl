(local tests [])

(local fs (require :fs))
(local json (require :json))
(local msdf (require :msdf-atlas-gen))
(local runtime (require :runtime))
(local test-verbose (os.getenv "TEST_VERBOSE"))

(fn log-line [msg]
  (print msg)
  (io.flush))

(fn msdf-atlas-gen-basic []
  (local assets-path (. runtime :assets-path))
  (local font-path (fs.join-path assets-path "ubuntu-font" "Ubuntu-R.ttf"))
  (assert (fs.exists font-path) (.. "missing font: " font-path))
  (when test-verbose
    (log-line (.. "[PATH] font=" font-path)))

  (local out-dir (fs.join-path "/tmp" "space/tests" "msdf-atlas-gen"))
  (when (fs.exists out-dir)
    (fs.remove-all out-dir))
  (fs.create-dirs out-dir)

  (local image-path (fs.join-path out-dir "Ubuntu-R.png"))
  (local json-path (fs.join-path out-dir "Ubuntu-R.json"))

  (msdf.generate {:font font-path
                  :chars "\"AaBbCc0123\""
                  :imageout image-path
                  :json json-path
                  :type "msdf"
                  :format "png"
                  :size 32
                  :pxrange 2
                  :pxalign "vertical"
                  :miterlimit 1.0
                  :angle 3.0
                  :coloringstrategy "inktrap"
                  :errorcorrection "auto-mixed"
                  :errordeviationratio 1.001
                  :errorimproveratio 1.001
                  :pxpadding 1
                  :aouterpxpadding [2 2 2 2]
                  :kerning true
                  :threads 1})

  (assert (fs.exists image-path) "image output missing")
  (assert (fs.exists json-path) "json output missing")

  (local parsed (json.loads (fs.read-file json-path)))
  (assert (= (. parsed :atlas :type) "msdf"))
  (assert (> (. parsed :atlas :width) 0))
  (assert (= (. parsed :atlas :distanceRange) 2)))

(table.insert tests {:name "msdf-atlas-gen generates ubuntu font atlas" :fn msdf-atlas-gen-basic})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "msdf-atlas-gen"
                       :tests tests})))

{:name "msdf-atlas-gen"
 :tests tests
 :main main}

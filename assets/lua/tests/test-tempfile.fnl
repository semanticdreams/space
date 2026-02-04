(local tests [])
(local fs (require :fs))
(local random (require :random))
(local tempfile (require :tempfile))

(var temp-counter 0)
(local tempfile-test-root (fs.join-path "/tmp/space/tests" "tempfile-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path tempfile-test-root (.. "tempfile-test-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn tempfile-gettempdir-non-empty []
  (local dir (tempfile.gettempdir))
  (assert (and dir (> (# dir) 0))))

(fn tempfile-mkstemp-creates-file []
  (with-temp-dir (fn [dir]
    (local path (tempfile.mkstemp {:dir dir :prefix "data_" :suffix ".txt"}))
    (assert (fs.exists path))
    (local info (fs.stat path))
    (assert info.is-file)
    (fs.remove path))))

(fn tempfile-mkdtemp-creates-dir []
  (with-temp-dir (fn [dir]
    (local path (tempfile.mkdtemp {:dir dir :prefix "build_" :suffix "_work"}))
    (assert (fs.exists path))
    (local info (fs.stat path))
    (assert info.is-dir)
    (fs.remove-all path))))

(fn tempfile-named-temporary-file-drop-deletes []
  (with-temp-dir (fn [dir]
    (local handle (tempfile.NamedTemporaryFile {:dir dir :prefix "app_" :suffix ".log"}))
    (assert (fs.exists handle.path))
    (handle:drop)
    (assert (not (fs.exists handle.path))))))

(fn tempfile-named-temporary-file-delete-false []
  (with-temp-dir (fn [dir]
    (local handle (tempfile.NamedTemporaryFile {:dir dir :delete false}))
    (assert (fs.exists handle.path))
    (handle:drop)
    (assert (fs.exists handle.path))
    (fs.remove handle.path))))

(fn tempfile-temporary-directory-drop-deletes []
  (with-temp-dir (fn [dir]
    (local handle (tempfile.TemporaryDirectory {:dir dir :prefix "tmp" :suffix ""}))
    (assert (fs.exists handle.path))
    (local info (fs.stat handle.path))
    (assert info.is-dir)
    (handle:drop)
    (assert (not (fs.exists handle.path))))))

(fn tempfile-custom-prefix-suffix []
  (with-temp-dir (fn [dir]
    (local prefix "x_")
    (local suffix ".bin")
    (local path (tempfile.mkstemp {:dir dir :prefix prefix :suffix suffix}))
    (local info (fs.stat path))
    (assert (= (string.sub info.name 1 (# prefix)) prefix))
    (assert (= (string.sub info.name (- (+ (# info.name) 1) (# suffix))) suffix))
    (fs.remove path))))

(fn tempfile-collision-retry-file []
  (with-temp-dir (fn [dir]
    (local prefix "c")
    (local suffix ".tmp")
    (random.seed 123456)
    (local hex1 (random.randbytes-hex 8))
    (local occupied (fs.join-path dir (.. prefix hex1 suffix)))
    (fs.write-file occupied "occupied")
    (random.seed 123456)
    (local path (tempfile.mkstemp {:dir dir :prefix prefix :suffix suffix}))
    (assert (not= path occupied))
    (assert (fs.exists path))
    (fs.remove path)
    (fs.remove occupied))))

(fn tempfile-collision-retry-dir []
  (with-temp-dir (fn [dir]
    (local prefix "d")
    (local suffix "_dir")
    (random.seed 654321)
    (local hex1 (random.randbytes-hex 8))
    (local occupied (fs.join-path dir (.. prefix hex1 suffix)))
    (fs.create-dir occupied)
    (random.seed 654321)
    (local path (tempfile.mkdtemp {:dir dir :prefix prefix :suffix suffix}))
    (assert (not= path occupied))
    (assert (fs.exists path))
    (fs.remove-all path)
    (fs.remove-all occupied))))

(table.insert tests {:name "gettempdir returns value" :fn tempfile-gettempdir-non-empty})
(table.insert tests {:name "mkstemp creates file" :fn tempfile-mkstemp-creates-file})
(table.insert tests {:name "mkdtemp creates directory" :fn tempfile-mkdtemp-creates-dir})
(table.insert tests {:name "NamedTemporaryFile drop deletes" :fn tempfile-named-temporary-file-drop-deletes})
(table.insert tests {:name "NamedTemporaryFile delete=false preserves" :fn tempfile-named-temporary-file-delete-false})
(table.insert tests {:name "TemporaryDirectory drop deletes" :fn tempfile-temporary-directory-drop-deletes})
(table.insert tests {:name "prefix/suffix options applied" :fn tempfile-custom-prefix-suffix})
(table.insert tests {:name "collision retry for mkstemp" :fn tempfile-collision-retry-file})
(table.insert tests {:name "collision retry for mkdtemp" :fn tempfile-collision-retry-dir})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "tempfile"
                       :tests tests})))

{:name "tempfile"
 :tests tests
 :main main}

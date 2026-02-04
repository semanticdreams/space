(local tests [])
(local fs (require :fs))
(local MockOpenGL (require :mock-opengl))

(fn with-mock [cb]
  (local mock (MockOpenGL))
  (mock:install)
  (local (ok result) (pcall cb mock))
  (mock:restore)
  (if ok
      result
      (error result)))

(fn temp-path [name]
  (local dir (fs.join-path "/tmp/space/tests" "render-capture"))
  (when (and fs fs.create-dirs)
    (fs.create-dirs dir))
  (fs.join-path dir name))

(fn capture-returns-bytes []
  (with-mock
    (fn [mock]
      (set app.viewport {:width 2 :height 2})
      (local bytes (string.rep "A" 16))
      (mock:set-read-pixels bytes)
      (set (. package.loaded "render-capture") nil)
      (local RenderCapture (require :render-capture))
      (local result (RenderCapture.capture {:mode "final"}))
      (assert (= result.width 2))
      (assert (= result.height 2))
      (assert (= result.bytes bytes))
      (local finish-calls (mock:get-gl-calls "glFinish"))
      (local read-calls (mock:get-gl-calls "glReadPixels"))
      (assert (= (length finish-calls) 1))
      (assert (= (length read-calls) 1))
      (local read-args (. (. read-calls 1) :args))
      (assert (= read-args.width 2))
      (assert (= read-args.height 2))
      true)))

(fn capture-writes-png []
  (with-mock
    (fn [mock]
      (set app.viewport {:width 2 :height 2})
      (local bytes (string.rep "\255" 16))
      (mock:set-read-pixels bytes)
      (set (. package.loaded "render-capture") nil)
      (local RenderCapture (require :render-capture))
      (local path (temp-path "final.png"))
      (when (fs.exists path)
        (fs.remove path))
      (local result (RenderCapture.capture {:mode "final"
                                            :path path
                                            :return-bytes true}))
      (assert (= result.path path))
      (assert (= result.bytes bytes))
      (assert (fs.exists path))
      (fs.remove path)
      true)))

(table.insert tests {:name "render capture returns bytes" :fn capture-returns-bytes})
(table.insert tests {:name "render capture writes png" :fn capture-writes-png})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "render-capture"
                       :tests tests})))

{:name "render-capture"
 :tests tests
 :main main}

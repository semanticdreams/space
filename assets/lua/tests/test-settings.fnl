(local tests [])
(local fs (require :fs))
(local toml (require :toml))
(local Settings (require :settings))
(local Camera (require :camera))
(local glm (require :glm))
(local MathUtils (require :math-utils))

(var temp-counter 0)
(local settings-temp-root (fs.join-path "/tmp/space/tests" "settings-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path settings-temp-root (.. "settings-test-" (os.time) "-" temp-counter)))

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

(fn write-config [dir filename data]
  (local path (fs.join-path dir filename))
  (fs.create-dirs dir)
  (fs.write-file path (toml.dumps data))
  path)

(local vec3-approx? (. MathUtils :vec3-approx?))
(local quat-approx? (. MathUtils :quat-approx?))
(local vec3->array (. MathUtils :vec3->array))
(local quat->array (. MathUtils :quat->array))
(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

(fn settings-merge-order []
  (with-temp-dir (fn [root]
    (local system-dir (fs.join-path root "system"))
    (local user-dir (fs.join-path root "user"))
    (write-config system-dir "settings.toml"
                  {:audio {:volume 0.2 :muted true}
                   :ui {:theme "dark"}
                   :list [1 2]})
    (write-config user-dir "settings.toml"
                  {:audio {:volume 0.4}
                   :ui {:scale 1.5}
                   :list [3]})
    (local settings (Settings {:config-dir user-dir
                               :site-config-dir system-dir
                               :filename "settings.toml"}))
    (assert (= (settings.get-value "audio.volume" nil) 0.4))
    (assert (= (settings.get-value "audio.muted" nil) true))
    (assert (= (settings.get-value "ui.theme" nil) "dark"))
    (assert (= (settings.get-value "ui.scale" nil) 1.5))
    (local list (settings.get-value "list" nil))
    (assert (= (length list) 1))
    (assert (= (. list 1) 3))
    true)))

(fn settings-write-user-only []
  (with-temp-dir (fn [root]
    (local system-dir (fs.join-path root "system"))
    (local user-dir (fs.join-path root "user"))
    (local system-path (write-config system-dir "settings.toml" {:sys {:only true}}))
    (local system-before (fs.read-file system-path))
    (local settings (Settings {:config-dir user-dir
                               :site-config-dir system-dir
                               :filename "settings.toml"}))
    (settings.set-value "audio.volume" 0.4)
    (local system-after (fs.read-file system-path))
    (assert (= system-before system-after) "system config should remain unchanged")
    (local user-path (fs.join-path user-dir "settings.toml"))
    (assert (fs.exists user-path) "user config should be written")
    (local user-content (fs.read-file user-path))
    (assert (string.find user-content "volume = 0.4" 1 true)
            (.. "expected user config to include volume = 0.4, got: " user-content))
    (assert (= (settings.get-value "sys.only" nil) true))
    true)))

(fn settings-camera-roundtrip []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (local camera (Camera {}))
    (camera:set-position (glm.vec3 1.2 3.4 5.6))
    (camera:set-rotation (glm.quat 0.9238795 0 0.3826834 0))
    (settings.set-value "camera.position" (vec3->array camera.position) {:save? false})
    (settings.set-value "camera.rotation" (quat->array camera.rotation) {:save? false})
    (settings.save)
    (local reload (Settings {:config-dir root :filename "settings.toml"}))
    (local loaded (Camera {}))
    (local stored-pos (array->vec3 (reload.get-value "camera.position" nil)))
    (local stored-rot (array->quat (reload.get-value "camera.rotation" nil)))
    (loaded:set-position stored-pos)
    (loaded:set-rotation stored-rot)
    (assert (vec3-approx? loaded.position camera.position)
            "camera position should roundtrip")
    (assert (quat-approx? loaded.rotation camera.rotation)
            "camera rotation should roundtrip")
    true)))

(table.insert tests {:name "Settings merge system then user" :fn settings-merge-order})
(table.insert tests {:name "Settings write only user config" :fn settings-write-user-only})
(table.insert tests {:name "Settings camera roundtrip" :fn settings-camera-roundtrip})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "settings"
                       :tests tests})))

{:name "settings"
 :tests tests
 :main main}

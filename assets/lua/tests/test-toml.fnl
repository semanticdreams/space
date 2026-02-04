(local tests [])
(local toml (require :toml))

(fn toml-loads-basic []
  (local input (.. "title = \"Space\"\n"
                   "items = [1, 2, 3]\n"
                   "[window]\n"
                   "width = 1280\n"
                   "height = 720\n"))
  (local parsed (toml.loads input))
  (assert (= (. parsed :title) "Space"))
  (assert (= (. parsed :window :width) 1280))
  (assert (= (. parsed :window :height) 720))
  (local items (. parsed :items))
  (assert (= (length items) 3))
  (assert (= (. items 1) 1))
  (assert (= (. items 3) 3)))

(fn toml-dumps-roundtrip []
  (local settings {:name "Space"
                   :window {:width 800 :height 600}
                   :flags {:fullscreen false}
                   :numbers [1 2 3]})
  (local output (toml.dumps settings))
  (local parsed (toml.loads output))
  (assert (= (. parsed :name) "Space"))
  (assert (= (. parsed :window :width) 800))
  (assert (= (. parsed :window :height) 600))
  (assert (= (. parsed :flags :fullscreen) false))
  (local numbers (. parsed :numbers))
  (assert (= (length numbers) 3))
  (assert (= (. numbers 2) 2)))

(fn toml-loads-rejects-date []
  (local input "started = 1979-05-27\n")
  (local (ok err) (pcall toml.loads input))
  (assert (not ok) "date/time values should be rejected")
  (assert (string.find err "date/time" 1 true) "error should mention date/time"))

(fn toml-dumps-rejects-noncontiguous-array []
  (local data {})
  (set (. data 1) "a")
  (set (. data 3) "c")
  (local (ok err) (pcall toml.dumps data))
  (assert (not ok) "non-contiguous arrays should be rejected")
  (assert (string.find err "string keys" 1 true) "error should mention string keys"))

(fn toml-dumps-rejects-unsupported-type []
  (local data {:name "Space" :fn (fn [] nil)})
  (local (ok err) (pcall toml.dumps data))
  (assert (not ok) "unsupported types should be rejected")
  (assert (string.find err "Unsupported" 1 true) "error should mention unsupported type"))

(table.insert tests {:name "toml loads basic values" :fn toml-loads-basic})
(table.insert tests {:name "toml dumps roundtrip" :fn toml-dumps-roundtrip})
(table.insert tests {:name "toml loads rejects date/time" :fn toml-loads-rejects-date})
(table.insert tests {:name "toml dumps rejects non-contiguous array" :fn toml-dumps-rejects-noncontiguous-array})
(table.insert tests {:name "toml dumps rejects unsupported type" :fn toml-dumps-rejects-unsupported-type})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "toml"
                       :tests tests})))

{:name "toml"
 :tests tests
 :main main}

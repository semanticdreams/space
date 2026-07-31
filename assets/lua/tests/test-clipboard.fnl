(local tests [])

(fn restore-gl [previous-gl]
  (if previous-gl
      (set (. package.loaded "gl") previous-gl)
      (set (. package.loaded "gl") nil)))

(fn clipboard-skip-error? [err-str]
  ;; Deterministically skip only when SDL video subsystem is unavailable
  ;; (headless/no-display). Do not mask real clipboard failures.
  (or (err-str:find "SDL video subsystem required")
      (err-str:find "video subsystem required")))

(fn probe-clipboard []
  (local previous-gl (. package.loaded "gl"))
  (set (. package.loaded "gl") nil)
  (local (require-ok real-gl-or-err) (pcall require :gl))
  (if (not require-ok)
      (do
        (restore-gl previous-gl)
        (error (.. "clipboard tests: require gl failed: " (tostring real-gl-or-err))))
      (let [real-gl real-gl-or-err]
        (if (not (and real-gl.clipboard-set real-gl.clipboard-get))
            (do
              (restore-gl previous-gl)
              (error "clipboard tests: real gl module missing clipboard-set/get"))
            (let [(probe-ok probe-err) (pcall #(real-gl.clipboard-set ":probe:"))]
              (restore-gl previous-gl)
              (if probe-ok
                  :available
                  (let [err-str (tostring probe-err)]
                    (if (clipboard-skip-error? err-str)
                        (do
                          (io.stderr:write (.. "[SKIP] clipboard tests: " err-str "\n"))
                          (io.stderr:flush)
                          :skip)
                        (error (.. "clipboard tests: clipboard probe failed unexpectedly: " err-str))))))))))

(local clipboard-status (probe-clipboard))

(fn with-real-gl [body]
  (assert (not (= clipboard-status :skip)) "real GL clipboard unavailable; tests should be skipped")
  (local previous-gl (. package.loaded "gl"))
  (set (. package.loaded "gl") nil)
  (local (_ real-gl) (pcall require :gl))
  (assert real-gl "real GL module unexpectedly missing")
  (local (ok err) (pcall #(body real-gl)))
  (restore-gl previous-gl)
  (when (not ok)
    (error err)))

(when (= clipboard-status :available)
  (fn clipboard-set-does-not-raise-stale-wayland-error []
    (with-real-gl
      (fn [gl]
        (gl.clipboard-set "test-stale-error-check"))))

  (fn clipboard-set-and-get-round-trips []
    (with-real-gl
      (fn [gl]
        (gl.clipboard-set "hello clipboard test")
        (assert (gl.clipboard-has) "clipboard-has should be true after set")
        (local text (gl.clipboard-get))
        (assert (= text "hello clipboard test")
                (.. "clipboard-get should return the set text, got: " (tostring text))))))

  (fn clipboard-preserves-utf8 []
    (with-real-gl
      (fn [gl]
        (gl.clipboard-set "café — em dash — ✓")
        (local text (gl.clipboard-get))
        (assert (= text "café — em dash — ✓")
                (.. "clipboard should preserve UTF-8 exactly, got: " (tostring text))))))

  (fn clipboard-preserves-newlines []
    (with-real-gl
      (fn [gl]
        (gl.clipboard-set "line one\nline two\nline three")
        (local text (gl.clipboard-get))
        (assert (= text "line one\nline two\nline three")
                (.. "clipboard should preserve newlines, got: " (tostring text))))))

  (fn clipboard-cleanup []
    (with-real-gl
      (fn [gl]
        (gl.clipboard-set ""))))

  (table.insert tests {:name "clipboard set does not raise stale wayland error" :fn clipboard-set-does-not-raise-stale-wayland-error})
  (table.insert tests {:name "clipboard set and get round-trips" :fn clipboard-set-and-get-round-trips})
  (table.insert tests {:name "clipboard preserves UTF-8" :fn clipboard-preserves-utf8})
  (table.insert tests {:name "clipboard preserves newlines" :fn clipboard-preserves-newlines})
  (table.insert tests {:name "clipboard cleanup" :fn clipboard-cleanup}))

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "clipboard"
                       :tests tests})))

{:name "clipboard"
 :tests tests
 :main main}

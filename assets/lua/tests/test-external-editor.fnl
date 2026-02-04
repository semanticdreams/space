(local _ (require :main))
(local fs (require :fs))
(local callbacks (require :callbacks))
(local ExternalEditor (require :external-editor))
(local tempfile (require :tempfile))

(local tests [])

(fn with-settings [settings f]
  (local previous app.settings)
  (set app.settings settings)
  (local (ok result) (pcall f))
  (set app.settings previous)
  (if ok
      result
      (error result)))

(fn make-settings [program args]
  {:get-value (fn [key fallback]
                (if (= key "external-editor.program")
                    program
                    (= key "external-editor.args")
                    args
                    fallback))})

(local wait-until
  (fn [pred]
    (callbacks.run-loop {:poll-jobs false
                         :poll-http false
                         :poll-process true
                         :sleep-ms 0
                         :timeout-ms 2000
                         :until pred})))

(fn external-editor-open-file-invokes-callback []
  (local path (tempfile.mkstemp {:prefix "external-editor-file-" :suffix ".txt"}))
  (fs.write-file path "before")
  (local settings
    (make-settings "sh"
                   ["-c" "printf 'after' > \"{path}\""]))
  (var received false)
  (with-settings settings
    (fn []
      (ExternalEditor.open-file path
                                (fn []
                                  (set received true)))))
  (local ok (wait-until (fn [] received)))
  (assert ok "open-file callback should be invoked")
  (assert (= (fs.read-file path) "after") "open-file should substitute {path}")
  (fs.remove path))

(fn external-editor-edit-string-returns-new-string []
  (local settings
    (make-settings "sh"
                   ["-c" "printf 'updated' > \"{path}\""]))
  (var received nil)
  (var path nil)
  (with-settings settings
    (fn []
      (set path (ExternalEditor.edit-string "original"
                                            (fn [value]
                                              (set received value))))))
  (local ok (wait-until (fn [] received)))
  (assert ok "edit-string callback should be invoked")
  (assert (= received "updated") "edit-string should return updated content")
  (assert (not (fs.exists path)) "edit-string should delete temp file by default"))

(fn external-editor-edit-string-allows-file-suffix []
  (local settings
    (make-settings "sh"
                   ["-c" "printf 'suffix' > \"{path}\""]))
  (var received nil)
  (var path nil)
  (with-settings settings
    (fn []
      (set path (ExternalEditor.edit-string "original"
                                            (fn [value]
                                              (set received value))
                                            {:file-suffix ".md"}))))
  (assert (string.find path "%.md$") "edit-string should apply file-suffix to temp path")
  (local ok (wait-until (fn [] received)))
  (assert ok "edit-string callback should be invoked")
  (assert (= received "suffix") "edit-string should return updated content")
  (assert (not (fs.exists path)) "edit-string should delete temp file by default"))

(fn external-editor-edit-string-raise-on-changed-errors []
  (local settings
    (make-settings "sh"
                   ["-c" "printf 'changed' > \"{path}\""]))
  (var received nil)
  (var received-err nil)
  (with-settings settings
    (fn []
      (ExternalEditor.edit-string "original"
                                  (fn [value err]
                                    (set received value)
                                    (set received-err err))
                                  {:raise-on-changed true})))
  (local ok (wait-until (fn [] received-err)))
  (assert ok "edit-string callback should be invoked with error when raise-on-changed trips")
  (assert (= received nil) "edit-string should not provide content when raise-on-changed trips")
  (assert (string.find (tostring received-err) "raise-on-changed" 1 true)))

(fn external-editor-unknown-placeholder-errors []
  (local path (tempfile.mkstemp {:prefix "external-editor-missing-" :suffix ".txt"}))
  (local settings
    (make-settings "sh"
                   ["-c" "echo {missing}"]))
  (local result
    (with-settings settings
      (fn []
        (local (ok err) (pcall ExternalEditor.open-file path (fn [] nil)))
        {:ok ok
         :err err})))
  (assert (not result.ok) "open-file should error on unknown placeholder")
  (assert (string.find (tostring result.err) "unknown placeholder" 1 true))
  (fs.remove path))

(table.insert tests {:name "external-editor.open-file invokes callback" :fn external-editor-open-file-invokes-callback})
(table.insert tests {:name "external-editor.edit-string returns new string" :fn external-editor-edit-string-returns-new-string})
(table.insert tests {:name "external-editor.edit-string supports file suffix" :fn external-editor-edit-string-allows-file-suffix})
(table.insert tests {:name "external-editor.edit-string raise-on-changed errors" :fn external-editor-edit-string-raise-on-changed-errors})
(table.insert tests {:name "external-editor errors on unknown placeholder" :fn external-editor-unknown-placeholder-errors})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "external-editor"
                       :tests tests})))

{:name "external-editor"
 :tests tests
 :main main}

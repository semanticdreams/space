(local glm (require :glm))
(local _ (require :main))
(local FsView (require :fs-view))
(local fs (require :fs))

(local tests [])

(fn make-vector-buffer []
  (local buffer {})
  (set buffer.allocate (fn [_self _count] 1))
  (set buffer.delete (fn [_self _handle] nil))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  buffer)

(fn make-test-ctx [opts]
  (local options (or opts {}))
  (local triangle (make-vector-buffer))
  (local text-buffer (make-vector-buffer))
  (local clickables (or options.clickables (assert app.clickables "test requires app.clickables")))
  (local hoverables (or options.hoverables (assert app.hoverables "test requires app.hoverables")))
  (local ctx {:triangle-vector triangle})
  (set ctx.get-text-vector (fn [_self _font] text-buffer))
  (set ctx.clickables clickables)
  (set ctx.hoverables hoverables)
  (set ctx.system-cursors options.cursors)
  (set ctx.icons options.icons)
  ctx)

(fn make-clickables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  (set stub.register-right-click (fn [_self _obj] nil))
  (set stub.unregister-right-click (fn [_self _obj] nil))
  (set stub.register-double-click (fn [_self _obj] nil))
  (set stub.unregister-double-click (fn [_self _obj] nil))
  stub)

(fn make-hoverables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  stub)

(fn make-system-cursors-stub []
  (local stub {})
  (set stub.set-cursor (fn [_self _name] nil))
  (set stub.reset (fn [_self] nil))
  stub)

(fn make-icons-stub []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}}
               :glyph-map {}})
  (set font.metadata.atlas {:width 1 :height 1})
  (local stub {:font font
               :codepoints {}})
  (var next-codepoint 3000)

  (fn set-codepoint [name value]
    (set (. stub.codepoints name) value)
    (set (. font.glyph-map value) glyph))

  (set-codepoint :folder 1111)
  (set-codepoint :docs 2222)

  (set stub.get
       (fn [self name]
           (local value (. self.codepoints name))
           (assert value (.. "Missing icon " name))
           value))
  (set stub.resolve
       (fn [self name]
           (local code (self:get name))
           {:type :font
            :codepoint code
            :font self.font}))
  stub)

(fn with-button-stubs [body]
  (local stubs {:clickables (make-clickables-stub)
                :hoverables (make-hoverables-stub)
                :cursors (make-system-cursors-stub)
                :icons (make-icons-stub)})
  (local (ok result) (pcall body stubs))
  (if ok
      result
      (error result)))

(var temp-counter 0)
(local fs-temp-root (fs.join-path "/tmp/space/tests" "fs-view-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path fs-temp-root (.. "fs-view-" (os.time) "-" temp-counter)))

(fn with-temp-dir [body]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall body dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn with-fs-view [path body]
  (with-button-stubs
    (fn [stubs]
      (local view ((FsView {:path path
                            :include-hidden false
                            :items-per-page 5})
                   (make-test-ctx stubs)))
      (local (ok result) (pcall body view stubs.icons))
      (view:drop)
      (if ok
          result
          (error result)))))

(fn fs-view-includes-parent-entry []
  (with-temp-dir (fn [root]
    (local child (fs.join-path root "alpha"))
    (fs.create-dir child)
    (with-fs-view child
      (fn [view]
        (local first (. view.items 1))
        (assert first.is-up? "first entry should be parent link")
        (assert (= first.path root)))))))

(fn fs-view-sorts-directories-before-files []
  (with-temp-dir (fn [root]
    (fs.create-dir (fs.join-path root "b-dir"))
    (fs.create-dir (fs.join-path root "a-dir"))
    (fs.write-file (fs.join-path root "c.txt") "c")
    (fs.write-file (fs.join-path root "b.txt") "b")
    (with-fs-view root
      (fn [view]
        (local names (icollect [_ entry (ipairs view.items)] entry.name))
        (assert (= (. names 1) ".."))
        (assert (= (. names 2) "a-dir"))
        (assert (= (. names 3) "b-dir"))
        (assert (= (. names 4) "b.txt"))
        (assert (= (. names 5) "c.txt")))))))

(fn fs-view-handle-entry-click-navigates []
  (with-temp-dir (fn [root]
    (local target-dir (fs.join-path root "inside"))
    (fs.create-dir target-dir)
    (with-fs-view root
      (fn [view]
        (var target-entry nil)
        (each [_ entry (ipairs view.items)]
          (when (= entry.path target-dir)
            (set target-entry entry)))
        (assert target-entry "expected directory entry")
        (view:handle-entry-click target-entry)
        (assert (= view.current-path target-dir)))))))

(fn fs-view-parent-entry-goes-up []
  (with-temp-dir (fn [root]
    (local child (fs.join-path root "nested"))
    (fs.create-dir child)
    (with-fs-view child
      (fn [view]
        (local parent-entry (. view.items 1))
        (assert parent-entry.is-up?)
        (view:handle-entry-click parent-entry)
        (assert (= view.current-path root)))))))

(fn fs-view-entry-builder-adds-icons []
  (with-temp-dir (fn [root]
    (local dir-path (fs.join-path root "folder"))
    (local file-path (fs.join-path root "notes.txt"))
    (fs.create-dir dir-path)
    (fs.write-file file-path "data")
    (with-fs-view root
      (fn [view icons]
        (local ctx (make-test-ctx {:icons icons}))
        (var dir-entry nil)
        (var file-entry nil)
        (each [_ entry (ipairs view.items)]
          (when (and entry.is-dir (not entry.is-up?))
            (set dir-entry entry))
          (when entry.is-file
            (set file-entry entry)))
        (assert dir-entry "expected directory entry")
        (assert file-entry "expected file entry")
        (fn assert-icon [entry expected-icon]
          (local button (view:build-entry entry ctx))
          (local padding button.child)
          (assert padding "button should provide padding child")
          (local flex padding.child)
          (assert flex "expected flex content")
          (local icon-meta (. flex.children 1))
          (local label-meta (. flex.children 2))
          (local icon-widget (and icon-meta icon-meta.element))
          (local label-widget (and label-meta label-meta.element))
          (assert icon-widget "missing icon widget")
          (assert label-widget "missing label widget")
          (local icon-codepoints (icon-widget:get-codepoints))
          (assert (= (. icon-codepoints 1) (icons:get expected-icon)))
          (local text
            (table.concat
              (icollect [_ cp (ipairs (label-widget:get-codepoints))]
                        (utf8.char cp))
              ""))
          (assert (= text (view:entry-label entry)))
          (button:drop))
        (assert-icon dir-entry :folder)
        (assert-icon file-entry :docs))))))

(table.insert tests {:name "FsView adds parent entry" :fn fs-view-includes-parent-entry})
(table.insert tests {:name "FsView sorts directories before files" :fn fs-view-sorts-directories-before-files})
(table.insert tests {:name "FsView navigates into directories" :fn fs-view-handle-entry-click-navigates})
(table.insert tests {:name "FsView parent entry navigates upward" :fn fs-view-parent-entry-goes-up})
(table.insert tests {:name "FsView builder composes icon labels" :fn fs-view-entry-builder-adds-icons})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "fs-view"
                       :tests tests})))

{:name "fs-view"
 :tests tests
 :main main}

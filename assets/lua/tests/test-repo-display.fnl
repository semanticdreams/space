(local _ (require :main))
(local tests [])
(local Display (require :repo/display))

(fn make-vector-buffer []
  (local buffer {})
  (set buffer.allocate (fn [_self _count] 1))
  (set buffer.delete (fn [_self _handle] nil))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  buffer)

(fn make-icons-stub []
  (local glyph {:advance 1
                :planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}
               :advance 1})
  (local stub {:font font
               :codepoints {:move_item 4242
                            :add 4242
                            :close 4242}})
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

(fn make-test-ctx []
  (local triangle (make-vector-buffer))
  (local text-buffer (make-vector-buffer))
  (local ctx {:triangle-vector triangle
              :pointer-target {}})
  (set ctx.get-text-vector (fn [_self _font] text-buffer))
  (set ctx.get-text-ssbo-batcher
       (fn [_self]
         {:upsert-text (fn [_batcher _key _opts] nil)
          :update-text-transform (fn [_batcher _key _opts] nil)
          :remove-text (fn [_batcher _key] nil)}))
  (set ctx.track-text-handle (fn [_self _font _handle _clip] nil))
  (set ctx.untrack-text-handle (fn [_self _font _handle] nil))
  (set ctx.clickables (assert (make-clickables-stub) "repo display test context requires clickables"))
  (set ctx.hoverables (assert (make-hoverables-stub) "repo display test context requires hoverables"))
  (set ctx.system-cursors (make-system-cursors-stub))
  (set ctx.icons (make-icons-stub))
  ctx)

(fn make-stub-workspace []
  (var clone-calls [])
  (var clone-errors {})
  (var create-task-calls [])
  (local stub-ws
    {:list-repos (fn [_self] [])
     :list-tasks (fn [_self _repo-id] [])
     :clone-repo (fn [_self url]
                   (when (. clone-errors url)
                     (error (. clone-errors url)))
                   (table.insert clone-calls url)
                   {:id (.. "stub-" (length clone-calls))
                    :owner "o"
                    :name "r"
                    :default-branch "main"
                    :profile "generic"
                    :clone-path "/tmp/stub"
                    :created-at (os.time)})
     :create-task (fn [_self repo-id prompt base]
                    (table.insert create-task-calls {:repo-id repo-id :prompt prompt :base base})
                    {:id (.. "task-" (length create-task-calls))
                     :status "created"
                     :prompt prompt
                     :created-at (os.time)})})
  {:workspace stub-ws
   :clone-calls clone-calls
   :clone-errors clone-errors
   :create-task-calls create-task-calls})

(fn save-app-state []
  {:workspace app.repo-workspace
   :next-frame app.next-frame
   :agent-presets app.agent-presets})

(fn restore-app-state [saved]
  (set app.repo-workspace saved.workspace)
  (set app.next-frame saved.next-frame)
  (set app.agent-presets saved.agent-presets))

(fn install-repo-workbench-fixture []
  (local saved (save-app-state))
  (local fixture (make-stub-workspace))
  (set app.repo-workspace fixture.workspace)
  (set app.agent-presets {:get-context (fn [] {:repos-available? false})
                          :set-context (fn [_ctx] nil)})
  (var captured-callback nil)
  (set app.next-frame
       (fn [cb]
         (assert (= (type cb) "function") "next-frame requires function")
         (set captured-callback cb)))
  {:saved saved
   :fixture fixture
   :get-captured (fn [] captured-callback)
   :teardown (fn [self]
               (restore-app-state self.saved))})

(fn safe-display-url-constructs-url []
  (local repo {:id "github.com-owner-repo"
               :host :github
               :host-raw "github.com"
               :owner "owner"
               :name "repo"
               :default-branch "main"
               :profile :generic
               :clone-path "/tmp/clone"
               :created-at (os.time)})
  (local url (Display.safe-display-url repo))
  (assert (= url "https://github.com/owner/repo.git")))

(fn safe-display-url-rejects-at-in-host-raw []
  (local repo {:id "id" :host-raw "token@github.com" :owner "x" :name "y"})
  (local (ok err) (pcall Display.safe-display-url repo))
  (assert (not ok) "should reject @ in host-raw")
  (assert (string.find (tostring err) "@" 1 true)))

(fn safe-display-url-rejects-at-in-owner []
  (local repo {:id "id" :host-raw "github.com" :owner "x@evil" :name "y"})
  (local (ok err) (pcall Display.safe-display-url repo))
  (assert (not ok) "should reject @ in owner"))

(fn safe-display-url-rejects-at-in-name []
  (local repo {:id "id" :host-raw "github.com" :owner "x" :name "y@evil"})
  (local (ok err) (pcall Display.safe-display-url repo))
  (assert (not ok) "should reject @ in name"))

(fn safe-display-url-rejects-query-string []
  (local repo {:id "id" :host-raw "github.com?evil=1" :owner "x" :name "y"})
  (local (ok err) (pcall Display.safe-display-url repo))
  (assert (not ok) "should reject query string"))

(fn safe-display-url-rejects-fragment []
  (local repo {:id "id" :host-raw "github.com" :owner "x" :name "y#frag"})
  (local (ok err) (pcall Display.safe-display-url repo))
  (assert (not ok) "should reject fragment"))

(fn safe-repo-summary-returns-safe-fields []
  (local repo {:id "github.com-owner-repo"
               :host :github
               :host-raw "github.com"
               :owner "owner"
               :name "repo"
               :default-branch "main"
               :profile :generic
               :clone-path "/tmp/clone"
               :created-at 12345})
  (local summary (Display.safe-repo-summary repo))
  (assert (= summary.id "github.com-owner-repo"))
  (assert (= summary.remote-url "https://github.com/owner/repo.git"))
  (assert (= summary.host :github))
  (assert (= summary.owner "owner"))
  (assert (= summary.name "repo"))
  (assert (= summary.default-branch "main"))
  (assert (= summary.profile :generic))
  (assert (= summary.created-at 12345))
  (assert (= summary.clone-path nil) "should not expose clone-path")
  (assert (= summary.host-raw nil) "should not expose host-raw"))

(fn safe-repo-summary-rejects-corrupt []
  (local repo {:id "id" :host-raw "github.com" :owner "@broken" :name "x"})
  (local (ok _err) (pcall Display.safe-repo-summary repo))
  (assert (not ok) "should reject corrupt owner"))

(fn safe-display-url-filters-mixed-repos []
  (local repos [{:id "ok" :host-raw "github.com" :owner "x" :name "y"}
                {:id "bad-at" :host-raw "token@github.com" :owner "x" :name "y"}
                {:id "bad-query" :host-raw "evil.com" :owner "x" :name "y?q=1"}
                {:id "also-ok" :host-raw "gitlab.com" :owner "alice" :name "proj"}])
  (local valid [])
  (each [_ repo (ipairs repos)]
    (local (ok _url) (pcall Display.safe-display-url repo))
    (when ok
      (table.insert valid repo)))
  (assert (= (length valid) 2) "only repos with safe fields should pass")
  (assert (= (. valid 1 :id) "ok") "first valid should be 'ok'")
  (assert (= (. valid 2 :id) "also-ok") "second valid should be 'also-ok'"))

(fn workbench-imports-repo-available-symbol []
  (local RepoBuiltins (require :llm/presets/builtins/repo))
  (local repo-available! RepoBuiltins.repo-available!)
  (assert (= (type repo-available!) "function") "repo-available! must be a function"))

(fn workbench-view-module-loads []
  (local (ok _v) (pcall require :repo/workbench-view))
  (assert ok "workbench-view module must load successfully"))

(fn workbench-clone-callback-skipped-after-drop []
  (local env (install-repo-workbench-fixture))
  (local (test-ok test-err)
    (pcall (fn []
             (local WorkbenchView (require :repo/workbench-view))
             (local (ok dialog-or-err) (pcall (fn []
                                                ((WorkbenchView {}) (make-test-ctx)))))
             (assert ok (.. "Failed to build WorkbenchView: " (tostring dialog-or-err)))
             (local dialog dialog-or-err)
             (local view dialog.__view)
             (assert view "workbench view should be exposed on dialog")
             (assert view.clone-input "clone-input should be exposed on view")
             (assert view.handle-clone "handle-clone should be exposed on view")
             (view.clone-input:set-text "https://github.com/test/repo.git")
             (view:handle-clone)
             (local captured (env:get-captured))
             (assert captured "clone should schedule next-frame callback")
             (dialog:drop)
             (assert view.dropped? "view.dropped? should be true after drop")
             (captured)
             (assert (= (length env.fixture.clone-calls) 0) "clone should not be called after drop"))))
  (env:teardown)
  (when (not test-ok)
    (error test-err)))

(fn workbench-create-task-callback-skipped-after-drop []
  (local env (install-repo-workbench-fixture))
  (local (test-ok test-err)
    (pcall (fn []
             (local WorkbenchView (require :repo/workbench-view))
             (local ctx (make-test-ctx))
             (local dialog ((WorkbenchView {}) ctx))
             (local view dialog.__view)
             (set view.selected-repo-id "test-repo")
             (assert view.prompt-input "prompt-input should be exposed on view")
             (assert view.base-input "base-input should be exposed on view")
             (assert view.handle-create-task "handle-create-task should be exposed on view")
             (view.prompt-input:set-text "Fix the bug")
             (view:handle-create-task)
             (local captured (env:get-captured))
             (assert captured "create-task should schedule next-frame callback")
             (dialog:drop)
             (assert view.dropped? "view.dropped? should be true after drop")
             (captured)
             (assert (= (length env.fixture.create-task-calls) 0) "create-task should not be called after drop"))))
  (env:teardown)
  (when (not test-ok)
    (error test-err)))

(fn workbench-create-task-preserves-repo-snapshot []
  (local env (install-repo-workbench-fixture))
  (local (test-ok test-err)
    (pcall (fn []
             (local WorkbenchView (require :repo/workbench-view))
             (local ctx (make-test-ctx))
             (local dialog ((WorkbenchView {}) ctx))
             (local view dialog.__view)
             (set view.selected-repo-id "repo-a")
             (view.prompt-input:set-text "Task for A")
             (view:handle-create-task)
             (local captured (env:get-captured))
             (assert captured "create-task should schedule next-frame callback")
             (set view.selected-repo-id "repo-b")
             (captured)
             (assert (= (length env.fixture.create-task-calls) 1) "create-task should be called for repo-a")
             (local call (. env.fixture.create-task-calls 1))
             (assert (= call.repo-id "repo-a") "create-task should use snapshotted repo-a id")
             (assert (= call.prompt "Task for A") "create-task should use snapshotted prompt")
             (dialog:drop))))
  (env:teardown)
  (when (not test-ok)
    (error test-err)))

(table.insert tests {:name "safe-display-url constructs url" :fn safe-display-url-constructs-url})
(table.insert tests {:name "safe-display-url rejects @ in host-raw" :fn safe-display-url-rejects-at-in-host-raw})
(table.insert tests {:name "safe-display-url rejects @ in owner" :fn safe-display-url-rejects-at-in-owner})
(table.insert tests {:name "safe-display-url rejects @ in name" :fn safe-display-url-rejects-at-in-name})
(table.insert tests {:name "safe-display-url rejects query string" :fn safe-display-url-rejects-query-string})
(table.insert tests {:name "safe-display-url rejects fragment" :fn safe-display-url-rejects-fragment})
(table.insert tests {:name "safe-repo-summary returns safe fields" :fn safe-repo-summary-returns-safe-fields})
(table.insert tests {:name "safe-repo-summary rejects corrupt" :fn safe-repo-summary-rejects-corrupt})
(table.insert tests {:name "safe-display-url filters mixed repos" :fn safe-display-url-filters-mixed-repos})
(table.insert tests {:name "workbench imports repo-available symbol" :fn workbench-imports-repo-available-symbol})
(table.insert tests {:name "workbench view module loads" :fn workbench-view-module-loads})
(table.insert tests {:name "workbench clone callback skipped after drop" :fn workbench-clone-callback-skipped-after-drop})
(table.insert tests {:name "workbench create-task callback skipped after drop" :fn workbench-create-task-callback-skipped-after-drop})
(table.insert tests {:name "workbench create-task preserves repo snapshot" :fn workbench-create-task-preserves-repo-snapshot})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "repo-display"
                       :tests tests})))

{:name "repo-display"
 :tests tests
 :main main}

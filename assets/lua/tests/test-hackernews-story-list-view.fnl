(local glm (require :glm))
(local HackerNewsStoryListView (require :graph/view/views/hackernews-story-list))
(local Signal (require :signal))

(fn make-vector-buffer []
    (local buffer {})
    (set buffer.allocate (fn [_self _count] 1))
    (set buffer.delete (fn [_self _handle] nil))
    (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
    (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
    (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
    (set buffer.set-float (fn [_self _handle _offset _value] nil))
    buffer)

(fn make-test-ctx []
    (local triangle (make-vector-buffer))
    (local text-buffer (make-vector-buffer))
    (local ctx {:triangle-vector triangle})
    (set ctx.get-text-vector (fn [_self _font] text-buffer))
    (set ctx.clickables (assert app.clickables "test requires app.clickables"))
    (set ctx.hoverables (assert app.hoverables "test requires app.hoverables"))
    ctx)

(fn make-future [value]
    {:on-complete (fn [cb]
                      (cb true value nil :test)
                      value)
     :cancel (fn [] nil)})

(fn build-view []
    (local items [{:id 101 :label "demo story"}])
    (local ctx (make-test-ctx))
    (local fetches {:count 0})
    (local updates (Signal))
    (local node {:kind "topstories"
                 :graph {:ctx ctx}
                 :items-changed updates})
    (set node.render-items (fn [_self] items))
    (set node.emit-items (fn [self]
                              (updates:emit items)
                              items))
    (set node.fetch-list (fn [self]
                              (set fetches.count (+ fetches.count 1))
                              (self:emit-items)))
    {:view ((HackerNewsStoryListView node) nil)
     :fetches fetches})

(local tests [{:name "hackernews story list view initializes fetch_list"
  :fn (fn []
          (local built (build-view))
          (local view built.view)
          (assert view "view should build")
          (assert view.fetch_list "view should expose fetch_list")
          ;; ensure invoking fetch_list does not error even with stub client
          (view:fetch_list)
          (assert (= built.fetches.count 1) "fetch_list should invoke node fetch handler")
          (when view.drop (view:drop)))}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hackernews-story-list-view"
                       :tests tests})))

{:name "hackernews-story-list-view"
 :tests tests
 :main main}

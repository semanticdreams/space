(local glm (require :glm))
(local _ (require :main))
(local Menu (require :menu))
(local MenuManager (require :menu-manager))
(local {: Layout} (require :layout))
(local fs (require :fs))
(local Graph (require :graph/init))
(local LinkEntityStore (require :entities/link))

(local tests [])

(fn make-icons-stub []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {65533 glyph
                           4242 glyph}})
  (local stub {:font font
               :codepoints {:note_add 4242
                            :link 4242
                            :playlist_add 4242
                            :exit_to_app 4242}})
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

(local default-icons (make-icons-stub))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "menu"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "menu-" (os.time) "-" temp-counter)))

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

(fn make-vector-buffer []
  (local buffer {})
  (set buffer.allocate (fn [_self _count] 1))
  (set buffer.delete (fn [_self _handle] nil))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  buffer)

(fn make-clickables-stub []
  (local state {:right-void nil
                :left-void nil})
  (local stub {:state state})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  (set stub.register-right-click (fn [_self _obj] nil))
  (set stub.unregister-right-click (fn [_self _obj] nil))
  (set stub.register-double-click (fn [_self _obj] nil))
  (set stub.unregister-double-click (fn [_self _obj] nil))
  (set stub.unregister-left-click-void-callback (fn [_self cb]
                                                  (when (= state.left-void cb)
                                                    (set state.left-void nil))))
  (set stub.register-left-click-void-callback
       (fn [_self cb]
         (set state.left-void cb)))
  (set stub.register-right-click-void-callback
       (fn [_self cb]
         (set state.right-void cb)))
  (set stub.unregister-right-click-void-callback
       (fn [_self cb]
         (when (= state.right-void cb)
           (set state.right-void nil))))
  stub)

(fn make-hoverables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  stub)

(fn make-test-ctx [opts]
  (local options (or opts {}))
  (local triangle (make-vector-buffer))
  (local text-buffer (make-vector-buffer))
  (local ctx {:triangle-vector triangle
              :pointer-target options.pointer-target
              :clickables options.clickables
              :hoverables options.hoverables})
  (set ctx.get-text-vector (fn [_self _font] text-buffer))
  (set ctx.icons (or options.icons default-icons))
  ctx)

(fn make-hud-stub [ctx]
  (local overlay-layout
    (Layout {:name "test-overlay"
             :measurer (fn [self]
                         (set self.measure (glm.vec3 0 0 0)))
             :layouter (fn [_self] nil)}))
  (local overlay-root {:children [] :layout overlay-layout})
  (local hud {:build-context ctx
              :overlay-root overlay-root})
  (set hud.add-overlay-child
       (fn [_self opts]
         (local builder (and opts opts.builder))
         (when builder
           (local element (builder ctx (or opts.builder-options {})))
           (table.insert overlay-root.children {:element element
                                               :position (or opts.position (glm.vec3 0 0 0))})
           (overlay-layout:add-child element.layout)
           element)))
  (set hud.remove-overlay-child
       (fn [_self element]
         (var removed false)
         (each [idx metadata (ipairs overlay-root.children)]
           (when (and (not removed) (= metadata.element element))
             (set removed true)
             (overlay-layout:remove-child idx)
             (table.remove overlay-root.children idx)))
         (when (and removed element element.drop)
           (element:drop))
         removed))
  (set hud.screen-pos-ray
       (fn [_self pos]
         {:origin (glm.vec3 (or pos.x 0) (or pos.y 0) 10)
          :direction (glm.vec3 0 0 -1)}))
  (set ctx.pointer-target hud)
  hud)

(fn menu-actions-fire-and-increment-depth []
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local state {:calls 0})
  (local menu
    ((Menu {:actions [{:name "Alpha"
                       :on-click (fn [_button _event]
                                   (set state.calls (+ state.calls 1)))}
                      {:name "Beta"}]})
     ctx))
  (assert (= (length menu.buttons) 2) "Menu should build one button per action")
  (local button (. menu.buttons 1))
  (button:on-click {:button 1})
  (assert (= state.calls 1) "Menu should forward button clicks to action handlers")
  (menu.layout:measurer)
  (set menu.layout.size menu.layout.measure)
  (set menu.layout.position (glm.vec3 0 0 0))
  (set menu.layout.rotation (glm.quat 1 0 0 0))
  (set menu.layout.depth-offset-index 5)
  (menu.layout:layouter)
  (local layout (. button :layout))
  (assert (= layout.depth-offset-index 6) "Menu should bump depth offset index"))

(fn menu-grows-downward-from-click []
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local menu
    ((Menu {:actions [{:name "First"} {:name "Second"}]})
     ctx))
  (menu.layout:measurer)
  (set menu.layout.size menu.layout.measure)
  (set menu.layout.position (glm.vec3 0 0 0))
  (set menu.layout.rotation (glm.quat 1 0 0 0))
  (set menu.layout.depth-offset-index 0)
  (menu.layout:layouter)
  (local first-layout (. (. menu.buttons 1) :layout))
  (local second-layout (. (. menu.buttons 2) :layout))
  (assert (< second-layout.position.y first-layout.position.y)
          "Menu items should stack downward from click position"))

(fn menu-manager-opens-and-closes []
  (reset-engine-events)
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local hud (make-hud-stub ctx))
  (local state {:fired 0})
  (local manager
    (MenuManager {:clickables clickables
                  :hud hud
                  :root-actions [{:name "Action"
                                  :fn (fn [_button _event]
                                        (set state.fired (+ state.fired 1)))}]}))
  (local cb clickables.state.right-void)
  (local left-cb clickables.state.left-void)
  (assert cb "MenuManager should register a right-click void callback")
  (assert left-cb "MenuManager should register a left-click void callback")
  (cb {:screen {:x 1 :y 2}})
  (assert (= (length hud.overlay-root.children) 1) "Root menu should open on void right click")
  (local element (. (. hud.overlay-root.children 1) :element))
  (local button (. element.buttons 1))
  (button:on-click {:button 1})
  (assert (= state.fired 1) "Menu actions should invoke handlers")
  (assert (= (length hud.overlay-root.children) 0) "Menu should close after action click")
  (cb {:screen {:x 3 :y 4}})
  (assert (= (length hud.overlay-root.children) 1) "Menu should reopen after close")
  (left-cb {})
  (assert (= (length hud.overlay-root.children) 0) "Menu should close on void left click")
  (cb {:screen {:x 5 :y 6}})
  (assert (= (length hud.overlay-root.children) 1) "Menu should open again")
  (app.engine.events.key-down.emit {:key 27})
  (assert (= (length hud.overlay-root.children) 0) "Menu should close on escape")
  (manager:drop))

(fn find-button-by-name [menu name]
  (var found nil)
  (each [idx action (ipairs (or menu.actions []))]
    (when (and (not found) (= action.name name))
      (set found (. menu.buttons idx))))
  found)

(fn menu-manager-root-show-link-entities-adds-related-nodes []
  (with-temp-dir
    (fn [root]
      (reset-engine-events)
      (local clickables (make-clickables-stub))
      (local hoverables (make-hoverables-stub))
      (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
      (local hud (make-hud-stub ctx))

      (local store (LinkEntityStore.LinkEntityStore {:base-dir root}))
      (local original-get-default LinkEntityStore.get-default)
      (set LinkEntityStore.get-default (fn [_opts] store))

      (local graph (Graph {:with-start false
                           :link-store store}))
      (local a (Graph.GraphNode {:key "node-a"}))
      (local b (Graph.GraphNode {:key "node-b"}))
      (graph:add-node a)
      (graph:add-node b)

      (local e1 (store:create-entity {:source-key "node-a" :target-key "node-b"}))
      (local e2 (store:create-entity {:source-key "node-c" :target-key "node-a"}))
      (local _e3 (store:create-entity {:source-key "node-d" :target-key "node-e"}))
      (local e4 (store:create-entity {:source-key "node-b" :target-key "node-x"}))

      (local original-graph app.graph)
      (local original-view app.graph-view)
      (set app.graph graph)
      (set app.graph-view {:selection {:selected-nodes [a]}})

      (local manager
        (MenuManager {:clickables clickables
                      :hud hud}))

      (local (ok err)
        (pcall
          (fn []
            (local cb clickables.state.right-void)
            (assert cb "MenuManager should register a right-click void callback")

            (cb {:screen {:x 1 :y 2}})
            (local element (. (. hud.overlay-root.children 1) :element))
            (local button (find-button-by-name element "Show link entities"))
            (assert button "Root context menu should include 'Show link entities'")

            (local before (graph:node-count))
            (button:on-click {:button 1})

            (assert (= (graph:node-count) (+ before 2))
                    "Show link entities should add link entity nodes for selected endpoints")
            (local n1 (graph:lookup (.. "link-entity:" (tostring e1.id))))
            (local n2 (graph:lookup (.. "link-entity:" (tostring e2.id))))
            (assert n1 "Should add link entity node for e1")
            (assert n2 "Should add link entity node for e2")
            (assert (not (graph:lookup (.. "link-entity:" (tostring e4.id))))
                    "Should not add link entity nodes unrelated to the selection")

            ;; Expanding selection to both a and b uses AND logic: only entities
            ;; whose source+target keys cover all selected keys are shown.
            ;; With [a b] selected, only e1 (node-a <-> node-b) matches;
            ;; e4 (node-b <-> node-x) does not because node-a is missing.
            (set app.graph-view {:selection {:selected-nodes [a b]}})
            (cb {:screen {:x 3 :y 4}})
            (local element-2 (. (. hud.overlay-root.children 1) :element))
            (local button-2 (find-button-by-name element-2 "Show link entities"))
            (assert button-2 "Root context menu should still include 'Show link entities'")
            (button-2:on-click {:button 1})
            (local n1-after (graph:lookup (.. "link-entity:" (tostring e1.id))))
            (local n2-after (graph:lookup (.. "link-entity:" (tostring e2.id))))
            (assert (= n1-after n1) "Action should not replace existing link entity nodes")
            (assert (= n2-after n2) "Existing link entity nodes from prior action should remain")
            (assert (not (graph:lookup (.. "link-entity:" (tostring e4.id))))
                    "AND filtering should exclude entities not covering all selected keys"))))

      (manager:drop)
      (graph:drop)
      (set app.graph original-graph)
      (set app.graph-view original-view)
      (set LinkEntityStore.get-default original-get-default)

      (when (not ok)
        (error err)))))

(table.insert tests {:name "Menu actions and depth offset" :fn menu-actions-fire-and-increment-depth})
(table.insert tests {:name "Menu grows downward from click" :fn menu-grows-downward-from-click})
(table.insert tests {:name "Menu manager opens and closes menu" :fn menu-manager-opens-and-closes})
(table.insert tests {:name "Menu root show link entities adds related nodes"
                     :fn menu-manager-root-show-link-entities-adds-related-nodes})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "menu"
                       :tests tests})))

{:name "menu"
 :tests tests
 :main main}

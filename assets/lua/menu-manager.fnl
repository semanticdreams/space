(local glm (require :glm))
(local Menu (require :menu))

(local SDLK_ESCAPE 27)

(fn show-link-entities-for-selection []
  (local graph app.graph)
  (when (not graph)
    (lua "return nil"))
  (local view app.graph-view)
  (local selected (or (and view view.selection view.selection.selected-nodes)
                      []))
  (when (<= (length selected) 0)
    (lua "return nil"))

  (local selected-keys {})
  (each [_ node (ipairs selected)]
    (local key (and node node.key))
    (when key
      (set (. selected-keys (tostring key)) true)))
  (when (= (next selected-keys) nil)
    (lua "return nil"))

  (local LinkEntityStore (require :entities/link))
  (local store (LinkEntityStore.get-default))
  (local {:LinkEntityNode LinkEntityNode} (require :graph/nodes/link-entity))
  (local entities (store:list-entities))
  (each [_ entity (ipairs (or entities []))]
    (local source-key (tostring (or (and entity entity.source-key) "")))
    (local target-key (tostring (or (and entity entity.target-key) "")))
    (local entity-keys {source-key true target-key true})
    (var all-match true)
    (each [k _ (pairs selected-keys) &until (not all-match)]
      (when (not (. entity-keys k))
        (set all-match false)))
    (when all-match
      (local id (tostring (or (and entity entity.id) "")))
      (when (> (string.len id) 0)
        (local key (.. "link-entity:" id))
        (when (not (graph:lookup key))
          (graph:add-node (LinkEntityNode {:entity-id id
                                           :store store}))))))
  nil)

(fn default-root-actions []
  (local actions [])
  (table.insert actions
                {:name "Create String Entity"
                 :icon "note_add"
                 :fn (fn [_button _event]
                       (local StringEntityStore (require :entities/string))
                       (local store (StringEntityStore.get-default))
                       (local entity (store:create-entity {}))
                       (when (and app.graph entity)
                         (local {:StringEntityNode StringEntityNode} (require :graph/nodes/string-entity))
                         (local node (StringEntityNode {:entity-id entity.id
                                                        :store store}))
                         (app.graph:add-node node)))})
  (table.insert actions
                {:name "Create Link Entity"
                 :icon "link"
                 :fn (fn [_button _event]
                       (local LinkEntityStore (require :entities/link))
                       (local store (LinkEntityStore.get-default))
                       (local selected (or (and app.graph-view
                                                app.graph-view.selection
                                                app.graph-view.selection.selected-nodes)
                                           []))
                       (local opts {})
                       (when (= (length selected) 2)
                         (set opts.source-key (or (. selected 1 :key) ""))
                         (set opts.target-key (or (. selected 2 :key) "")))
                       (local entity (store:create-entity opts))
                       (when (and app.graph entity)
                         (local {:LinkEntityNode LinkEntityNode} (require :graph/nodes/link-entity))
                         (local node (LinkEntityNode {:entity-id entity.id
                                                      :store store}))
                         (app.graph:add-node node)))})
  (table.insert actions
                {:name "Show link entities"
                 :icon "link"
                 :fn (fn [_button _event]
                       (show-link-entities-for-selection))})
  (table.insert actions
                {:name "Create List Entity"
                 :icon "playlist_add"
                 :fn (fn [_button _event]
                       (local ListEntityStore (require :entities/list))
                       (local store (ListEntityStore.get-default))
                       (local selected (or (and app.graph-view
                                                app.graph-view.selection
                                                app.graph-view.selection.selected-nodes)
                                           []))
                       (local items [])
                       (each [_ node (ipairs selected)]
                         (when (and node node.key)
                           (table.insert items node.key)))
                       (local entity (store:create-entity {:items items}))
                       (when (and app.graph entity)
                         (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
                         (local node (ListEntityNode {:entity-id entity.id
                                                      :store store}))
                         (app.graph:add-node node)))})

  (table.insert actions
                {:name "Demo Browser"
                 :fn (fn [_button _event]
                       (local scene app.scene)
                       (when (and scene scene.add-demo-browser)
                         (scene:add-demo-browser)))})
  (table.insert actions
                {:name "Quit"
                 :icon "exit_to_app"
                 :fn (fn [_button _event]
                       (when (and app.engine app.engine.quit)
                         (app.engine.quit)))})
  actions)

(fn MenuManager [opts]
  (local options (or opts {}))
  (local clickables (or options.clickables app.clickables))
  (local hud (or options.hud app.hud))
  (local root-actions (or options.root-actions (default-root-actions)))

  (assert clickables "MenuManager requires clickables")
  (assert hud "MenuManager requires hud")

  (var active-menu nil)
  (var right-click-callback nil)
  (var left-click-callback nil)
  (var mouse-button-handler nil)
  (var key-down-handler nil)

  (fn active? [_self]
    (not (= active-menu nil)))

  (fn screen-pos->hud [screen]
    (local x (or (and screen screen.x) 0))
    (local y (or (and screen screen.y) 0))
    (local ray (and hud hud.screen-pos-ray (hud:screen-pos-ray {:x x :y y})))
    (if (and ray ray.origin ray.direction)
        (let [dz (or ray.direction.z 0)
              t (if (not (= dz 0)) (/ (- 0 ray.origin.z) dz) 0)]
          (+ ray.origin (* ray.direction t)))
        (glm.vec3 x y 0)))

  (fn close []
    (when active-menu
      (when (and hud hud.remove-overlay-child)
        (hud:remove-overlay-child active-menu))
      (set active-menu nil)
      ))

  (fn wrap-actions [actions]
    (icollect [_ action (ipairs (or actions []))]
      {:name (or action.name action.text)
       :text action.text
       :icon action.icon
       :variant action.variant
       :padding action.padding
       :on-click (fn [button event]
                   (when action.fn
                     (action.fn button event))
                   (when action.handler
                     (action.handler button event))
                   (when action.on-click
                     (action.on-click button event))
                   (close))}))

  (fn open [self opts]
    (local open-opts (or opts {}))
    (local actions (wrap-actions open-opts.actions))
    (local position (or open-opts.position (glm.vec3 0 0 0)))
    (local overlay-layout (and hud hud.overlay-root hud.overlay-root.layout))
    (local base-depth (or (and overlay-layout overlay-layout.depth-offset-index) 0))
    (local depth-offset-index (or open-opts.depth-offset-index (+ base-depth 100)))
    (close)
    (when (and hud hud.add-overlay-child)
      (local builder (Menu {:actions actions}))
      (set active-menu (hud:add-overlay-child {:builder builder
                                               :position position
                                               :depth-offset-index depth-offset-index}))))

  (fn open-root [self event]
    (local screen (and event event.screen))
    (local position (screen-pos->hud screen))
    (open nil {:actions root-actions
               :position position
               :ignore-button (or (and event event.button) 3)}))

  (fn on-left-click-void [_event]
    (when active-menu
      (close)))

  (fn on-key-down [payload]
    (when (and active-menu payload (= payload.key SDLK_ESCAPE))
      (close)))

  (fn drop [self]
    (close)
    (when (and clickables right-click-callback)
      (clickables:unregister-right-click-void-callback right-click-callback)
      (set right-click-callback nil))
    (when (and clickables left-click-callback)
      (clickables:unregister-left-click-void-callback left-click-callback)
      (set left-click-callback nil))
    (when (and app.engine app.engine.events key-down-handler)
      (app.engine.events.key-down:disconnect key-down-handler true)
      (set key-down-handler nil)))

  (set right-click-callback
       (fn [event]
         (open-root nil event)))
  (clickables:register-right-click-void-callback right-click-callback)
  (set left-click-callback
       (fn [event]
         (on-left-click-void event)))
  (clickables:register-left-click-void-callback left-click-callback)

  (when (and app.engine app.engine.events)
    (set key-down-handler
         (app.engine.events.key-down:connect on-key-down)))

  {:open open
   :open-root open-root
   :close (fn [_self] (close))
   :drop drop
   :active? active?
   :menu (fn [] active-menu)})

MenuManager

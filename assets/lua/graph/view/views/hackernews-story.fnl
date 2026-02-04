(local glm (require :glm))
(local Button (require :button))
(local ListView (require :list-view))
(local Padding (require :padding))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Input (require :input))
(local {: Flex : FlexChild} (require :flex))

(fn disable-button [button ctx]
    (set button.disabled? true)
    (local clickables (assert ctx.clickables "disable-button requires ctx.clickables"))
    (local hoverables (assert ctx.hoverables "disable-button requires ctx.hoverables"))
    (clickables:unregister button)
    (clickables:unregister-right-click button)
    (clickables:unregister-double-click button)
    (hoverables:unregister button)
    (when button.clicked
        (button.clicked:clear))
    (when button.right-clicked
        (button.right-clicked:clear))
    (when button.double-clicked
        (button.double-clicked:clear))
    (set button.on-click (fn [_btn _event] nil))
    (when button.focus-node
        (button.focus-node:drop)
        (set button.focus-node nil))
    (when button.update-background-color
        (set button.background-color (glm.vec4 0.25 0.25 0.25 0.5))
        (button:update-background-color {:mark-layout-dirty? false})))

(fn HackerNewsStoryView [node opts]
    (local options (or opts {}))
    (local target (or node options.node))
    (local list-name (or options.list-name
                         (.. "hackernews-story-" (tostring (or (and target target.id) "unknown")))))
    (local initial-rows (or options.rows []))
    (local initial-actions (or options.actions []))

    (fn build [ctx]
        (local context (or ctx options.ctx (and target target.graph target.graph.ctx)))
        (assert context "HackerNewsStoryView requires a build context")

        (local view {:layout nil
                     :actions initial-actions
                     :rows initial-rows})

        (local list-builder
            (ListView {:items []
                       :name list-name
                       :item-spacing 0.3
                       :builder (fn [entry child-ctx]
                                    (if (= entry.type :body)
                                        ((Input {:text entry.text
                                                 :multiline? true
                                                 :min-lines 6
                                                 :max-lines 30})
                                         child-ctx)
                                        (if (= entry.type :actions)
                                            (let [buttons
                                                  (icollect [_ action (ipairs entry.actions)]
                                                      (do
                                                        (local enabled? (not (= action.enabled? false)))
                                                        (local button
                                                            ((Button {:text action.label
                                                                      :focusable? enabled?
                                                                      :variant (if enabled?
                                                                                 :solid
                                                                                 :ghost)
                                                                      :on-click (fn [_btn _event]
                                                                                     (when (and enabled? action.on-click)
                                                                                         (action.on-click)))})
                                                             child-ctx))
                                                        (set button.enabled? enabled?)
                                                        (when (not enabled?)
                                                            (disable-button button child-ctx))
                                                        button))]
                                                (local children
                                                    (icollect [_ button (ipairs buttons)]
                                                        (FlexChild (fn [_] button) 0)))
                                                ((Padding {:edge-insets [0.2 0.1]
                                                           :child (Flex {:axis :x
                                                                         :spacing 0.2
                                                                         :children children})})
                                                 child-ctx))
                                            ((Padding {:edge-insets [0.3 0.2]
                                                       :child (Text {:text entry.text
                                                                     :style (TextStyle (or entry.style {}))})})
                                             child-ctx))))}))

        (local list (list-builder context))

        (tset view :layout list.layout)
        (tset view :set-rows
              (fn [self rows]
                  (set self.rows rows)
                  (list:set-items rows)))
        (tset view :set-actions
              (fn [self actions]
                  (set self.actions actions)))
        (tset view :add-user-node
              (fn [_self username]
                  (when (and target target.add-user-node)
                      (target:add-user-node username))))
        (tset view :fetch
              (fn [_self]
                  (when (and target target.fetch)
                      (target:fetch))))

        (local rows-signal (and target target.rows-changed))
        (local actions-signal (and target target.actions-changed))
        (local rows-handler (and rows-signal
                                 (fn [rows]
                                     (view:set-rows rows))))
        (local actions-handler (and actions-signal
                                    (fn [actions]
                                        (view:set-actions actions))))

        (when rows-signal
            (rows-signal:connect rows-handler))
        (when actions-signal
            (actions-signal:connect actions-handler))

        (tset view :drop
              (fn [_self]
                  (when rows-signal
                      (rows-signal:disconnect rows-handler true))
                  (when actions-signal
                      (actions-signal:disconnect actions-handler true))
                  (list:drop)))

        (view:set-rows (or (and target target.emit-rows (target:emit-rows))
                           (and target target.build-rows (target:build-rows))
                           initial-rows))
        (view:set-actions (or (and target target.emit-actions (target:emit-actions))
                               (and target target.make-actions (target:make-actions target.item))
                               initial-actions))
        view))

HackerNewsStoryView

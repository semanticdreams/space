(local ListView (require :list-view))
(local Padding (require :padding))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Input (require :input))

(fn HackerNewsUserView [node opts]
    (local options (or opts {}))
    (local target (or node options.node))
    (local list-name (.. "hackernews-user-" (or options.user-id (and target target.id) "unknown")))
    (local initial-rows (or options.rows []))

    (fn build [ctx]
        (local context (or ctx options.ctx (and target target.graph target.graph.ctx)))
        (assert context "HackerNewsUserView requires a build context")

        (local view {:layout nil
                     :rows initial-rows
                     :user (or options.user (and target target.user))
                     :error (or options.error (and target target.error))})

        (local list-builder
            (ListView {:items []
                       :name list-name
                       :item-spacing 0.25
                       :builder (fn [entry child-ctx]
                                    (if (= entry.type :body)
                                        ((Input {:text entry.text
                                                 :multiline? true
                                                 :min-lines 4
                                                 :max-lines 16})
                                         child-ctx)
                                        ((Padding {:edge-insets [0.3 0.2]
                                                   :child (Text {:text entry.text
                                                                 :style (TextStyle (or entry.style {}))})})
                                         child-ctx)))}))

        (local list (list-builder context))

        (tset view :layout list.layout)
        (tset view :set-rows
              (fn [self rows]
                  (set self.rows rows)
                  (set self.user (and target target.user))
                  (set self.error (and target target.error))
                  (list:set-items rows)))
        (tset view :set-user
              (fn [self user]
                  (set self.user user)))
        (tset view :set-error
              (fn [self err]
                  (set self.error err)))
        (tset view :fetch
              (fn [self]
                  (when (and target target.fetch)
                      (target:fetch))))

        (local rows-signal (and target target.rows-changed))
        (local rows-handler (and rows-signal
                                 (fn [rows]
                                     (view:set-rows rows))))
        (when rows-signal
            (rows-signal:connect rows-handler))
        (tset view :drop
              (fn [_self]
                  (when rows-signal
                      (rows-signal:disconnect rows-handler true))
                  (list:drop)))

        (view:set-rows (or (and target target.emit-rows (target:emit-rows))
                          (and target target.build-rows (target:build-rows))
                          initial-rows))
        view))

HackerNewsUserView

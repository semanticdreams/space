(local glm (require :glm))
(local Text (require :text))
(local {: StatusPanelLayout} (require :hud-status-panel-layout))
(local {: truncate-with-ellipsis} (require :graph/view/utils))

(fn keyword->label [value fallback]
  (local raw (and value (tostring value)))
  (local trimmed
    (if (and raw (> (string.len raw) 0) (= (string.sub raw 1 1) ":"))
        (string.sub raw 2)
        raw))
  (or trimmed fallback))

(fn current-state-text [states]
  (local state-name (and states states.active-name
                         (states.active-name)))
  (local label (keyword->label state-name "Unknown"))
  (local first-line (or (string.match label "^[^\n]*") label))
  (local trimmed (truncate-with-ellipsis first-line 32))
  (string.format "State: %s" trimmed))

(fn current-focus-text [manager]
  (local focus-node (and manager manager.get-focused-node
                         (manager:get-focused-node)))
  (local label (keyword->label (and focus-node focus-node.name) "None"))
  (local first-line (or (string.match label "^[^\n]*") label))
  (local trimmed (truncate-with-ellipsis first-line 32))
  (string.format "Focus: %s"
                 trimmed))

(fn StatusPanel [_opts]
  (fn build [ctx]
    (local hud (or ctx.pointer-target {}))
    (local focus-manager (or hud.focus-manager (and ctx ctx.focus ctx.focus.manager)))
    (local states-instance (and ctx ctx.states))
    (var state-text-entity nil)
    (var focus-text-entity nil)
    (local state-text (Text {:text (current-state-text states-instance)}))
    (local focus-text (Text {:text (current-focus-text focus-manager)}))

    (local build-state-text
      (fn [child-ctx]
        (set state-text-entity (state-text child-ctx))
        state-text-entity))

    (local build-focus-text
      (fn [child-ctx]
        (set focus-text-entity (focus-text child-ctx))
        focus-text-entity))

    (var state-listener nil)
    (var focus-focus-listener nil)
    (var focus-blur-listener nil)

    (fn update-state-label []
      (when state-text-entity
        (state-text-entity:set-text (current-state-text states-instance))))

    (fn update-focus-label []
      (when focus-text-entity
        (focus-text-entity:set-text (current-focus-text focus-manager))))

    (fn attach-listeners []
      (when (and states-instance states-instance.changed (not state-listener))
        (set state-listener
             (states-instance.changed.connect
               (fn [_event]
                 (update-state-label)))))
      (when (and focus-manager focus-manager.focus-focus (not focus-focus-listener))
        (set focus-focus-listener
             (focus-manager.focus-focus.connect
               (fn [_event]
                 (update-focus-label)))))
      (when (and focus-manager focus-manager.focus-blur (not focus-blur-listener))
        (set focus-blur-listener
             (focus-manager.focus-blur.connect
               (fn [_event]
                 (update-focus-label))))))

    (fn detach-listeners []
      (when (and state-listener states-instance states-instance.changed)
        (states-instance.changed.disconnect state-listener true)
        (set state-listener nil))
      (when (and focus-focus-listener focus-manager focus-manager.focus-focus)
        (focus-manager.focus-focus.disconnect focus-focus-listener true)
        (set focus-focus-listener nil))
      (when (and focus-blur-listener focus-manager focus-manager.focus-blur)
        (focus-manager.focus-blur.disconnect focus-blur-listener true)
        (set focus-blur-listener nil)))

    (local panel
      ((StatusPanelLayout {:state-builder build-state-text
                           :focus-builder build-focus-text}) ctx))

    (update-state-label)
    (update-focus-label)
    (attach-listeners)

    (local original-drop panel.drop)
    (set panel.drop
         (fn [self]
           (detach-listeners)
           (when original-drop
             (original-drop self))))
    panel))

(local exports {:StatusPanel StatusPanel})

(setmetatable exports {:__call (fn [_ ...]
                                 (StatusPanel ...))})

exports

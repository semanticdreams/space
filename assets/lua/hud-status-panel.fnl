(local glm (require :glm))
(local Text (require :text))
(local CommandHints (require :command-hints))
(local {: StatusPanelLayout} (require :hud-status-panel-layout))
(local {: truncate-with-ellipsis} (require :graph/view/utils))
(local {: codepoints-from-text : measure-single-line} (require :text-utils))

(local toggle-text (.. "[" (CommandHints.key-label CommandHints.KEY_F1) "] more"))

(fn keyword->label [value default-label]
  (local raw (and value (tostring value)))
  (local trimmed
    (if (and raw (> (string.len raw) 0) (= (string.sub raw 1 1) ":"))
        (string.sub raw 2)
        raw))
  (or trimmed default-label))

(fn current-state-label [states]
  (local state-name (and states states.active-name
                         (states:active-name)))
  (local label (keyword->label state-name "unknown"))
  (local first-line (or (string.match label "^[^\n]*") label))
  (truncate-with-ellipsis first-line 24))

(fn current-focus-label [manager]
  (local focus-node (and manager manager.get-focused-node
                         (manager:get-focused-node)))
  (local label (keyword->label (and focus-node focus-node.name) "none"))
  (local first-line (or (string.match label "^[^\n]*") label))
  (truncate-with-ellipsis first-line 24))

(fn current-focus-manager [hud]
  (assert hud "StatusPanel requires a HUD")
  (assert hud.get-focus-manager "StatusPanel HUD must expose :get-focus-manager")
  (hud:get-focus-manager))

(fn info-text [states manager]
  (.. "State: "
      (current-state-label states)
      "   Focus: "
      (current-focus-label manager)))

(fn measure-line-width [text style]
  (local layout {:measure (glm.vec3 0)})
  (measure-single-line layout (codepoints-from-text text) style)
  (. layout.measure 1))

(fn StatusPanel [_opts]
  (local options (or _opts {}))
  (fn build [ctx]
    (local hud (assert ctx.pointer-target "StatusPanel requires ctx.pointer-target"))
    (local command-hints
      (if options.commands-builder
          hud.command-hints
          (assert hud.command-hints
                  "StatusPanel requires hud.command-hints when using default commands builder")))
    (var commands-entity nil)
    (var info-entity nil)
    (var last-commands-text nil)
    (var last-info-text nil)

    (local commands-builder
      (or options.commands-builder
          (fn [child-ctx]
            (set commands-entity ((Text {:text ""}) child-ctx))
            commands-entity)))
    (local info-builder
      (or options.info-builder
          (fn [child-ctx]
            (set info-entity ((Text {:text ""}) child-ctx))
            info-entity)))

    (fn refresh-commands []
      (when (and command-hints commands-entity)
        (local next-text command-hints.collapsed)
        (when (not (= next-text last-commands-text))
          (set last-commands-text next-text)
          (commands-entity:set-text next-text))))

    (fn refresh-info []
      (when info-entity
        (local next-text (info-text hud.states (current-focus-manager hud)))
        (when (not (= next-text last-info-text))
          (set last-info-text next-text)
          (info-entity:set-text next-text))))

    (fn commands-min-width []
      (local style (and commands-entity commands-entity.style))
      (if style
          (measure-line-width toggle-text style)
          nil))

    (local panel
      ((StatusPanelLayout {:commands-builder commands-builder
                           :info-builder info-builder
                           :commands-min-width-provider commands-min-width
                           :body-builder options.body-builder})
       ctx))

    (fn update [_self]
      (when command-hints
        (command-hints:update {:max-width (and panel panel.commands-max-width
                                               (panel:commands-max-width))
                               :style (and commands-entity commands-entity.style)}))
      (refresh-commands)
      (refresh-info))

    (set panel.update update)
    (update nil)
    panel))

(local exports {:StatusPanel StatusPanel})

(setmetatable exports {:__call (fn [_ ...]
                                 (StatusPanel ...))})

exports

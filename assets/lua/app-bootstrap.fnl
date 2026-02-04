(fn init-themes []
  (local Themes (require :themes))
  (set app.themes (Themes))
  (app.themes.add-theme :dark (require :dark-theme))
  (app.themes.add-theme :light (require :light-theme))
  (local stored-theme
    (and app.settings app.settings.get-value
         (app.settings.get-value "ui.theme" nil)))
  (local resolved-theme
    (if (= stored-theme "light")
        :light
        (if (= stored-theme "dark")
            :dark
            nil)))
  (app.themes.set-theme (or resolved-theme :dark))
  app.themes)

(fn init-input-systems []
  (local Intersectables (require :intersectables))
  (local Clickables (require :clickables))
  (local Hoverables (require :hoverables))
  (local Movables (require :movables))
  (local Resizables (require :resizables))
  (local SystemCursors (require :system-cursors))
  (set app.intersectables (Intersectables))
  (set app.clickables (Clickables {:intersectables app.intersectables}))
  (set app.hoverables (Hoverables {:intersectables app.intersectables}))
  (set app.movables (Movables {:intersectables app.intersectables}))
  (set app.resizables (Resizables {:intersectables app.intersectables}))
  (set app.system-cursors (SystemCursors))
  {:intersectables app.intersectables
   :clickables app.clickables
   :hoverables app.hoverables
   :movables app.movables
   :resizables app.resizables
   :system-cursors app.system-cursors})

(fn init-renderers [opts]
  (local Renderers (require :renderers))
  (set app.renderers (Renderers))
  (local options (or opts {}))
  (when (and app.renderers options.viewport)
    (app.renderers:on-viewport-changed options.viewport))

  ; Apply persisted UI settings that affect renderers.
  (when (and app.settings app.settings.get-value app.renderers app.renderers.skybox)
    (local skybox-name (app.settings.get-value "ui.skybox" nil))
    (when (and skybox-name (= (type skybox-name) :string) (> (# skybox-name) 0))
      (app.renderers.skybox:set-skybox (.. "skyboxes/" skybox-name))))

  app.renderers)

(fn init-icons []
  (local Icons (require :icons))
  (set app.icons (Icons))
  app.icons)

(fn init-states []
  (local States (require :states))
  (set app.states (States))
  (app.states.add-state :normal ((require :normal-state)))
  (app.states.add-state :leader ((require :leader-state)))
  (app.states.add-state :quit ((require :quit-state)))
  (app.states.add-state :text ((require :text-state)))
  (app.states.add-state :insert ((require :insert-state)))
  (app.states.add-state :camera ((require :camera-state)))
  (app.states.add-state :fpc ((require :fpc-state)))
  (app.states.add-state :car ((require :car-state)))
  (app.states.add-state :tetris ((require :tetris-state)))
  (app.states.set-state :normal)
  app.states)

{:init-themes init-themes
 :init-input-systems init-input-systems
 :init-renderers init-renderers
 :init-icons init-icons
 :init-states init-states}

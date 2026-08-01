(local os os)
(local string string)
(local debug debug)
(local logging (require :logging))
(local glm (require :glm))

(local FlamegraphProfiler (require :flamegraph-profiler))
(local NextLayout (require :next-app/layout))
(local NextFlex (require :next-app/flex))
(local PanelWidget (require :next-app/panel-widget))
(local ToggleWidget (require :next-app/toggle-widget))
(local ProgressWidget (require :next-app/progress-widget))

(local default-output-path "prof/next-layout.folded")

(fn to-lower [value]
  (and value (string.lower value)))

(fn use-default-output? [value]
  (local lower (to-lower value))
  (or (= value nil)
      (= value "")
      (= value "1")
      (= lower "true")
      (= lower "on")))

(fn flamegraph-disabled? [value]
  (local lower (to-lower value))
  (and value (or (= value "0")
                 (= lower "false")
                 (= lower "off"))))

(fn resolve-output-path []
  (local env (os.getenv "SPACE_FENNEL_FLAMEGRAPH"))
  (if (flamegraph-disabled? env)
      nil
      (if (use-default-output? env)
          default-output-path
          env)))

(local output-path (resolve-output-path))
(when (not output-path)
  (logging.info "SPACE_FENNEL_FLAMEGRAPH disabled; not recording next-layout profile.")
  (os.exit 0))

(local profiler (FlamegraphProfiler {:output-path output-path}))

(fn build-profile-tree []
  (local rows [])
  (local stub-clickables {:register (fn [_ _] nil) :unregister (fn [_ _] nil)})
  (local stub-hoverables {:register (fn [_ _] nil) :unregister (fn [_ _] nil)})
  (for [i 1 180]
    (local row
      (NextFlex.Flex {:name (.. "row-" i)
                      :axis :x
                      :gap 0.02
                      :children [(NextFlex.FlexChild (ToggleWidget {:width 0.26
                                                                     :height 0.11
                                                                     :clickables stub-clickables
                                                                     :hoverables stub-hoverables
                                                                     :checked? (= (% i 2) 0)}) 0)
                                 (NextFlex.FlexChild (ProgressWidget {:value (/ (% i 10) 10)
                                                                       :width 0.34
                                                                       :height 0.08}) 1)
                                 (NextFlex.FlexChild (PanelWidget {:width 0.16
                                                                   :height 0.08
                                                                   :color (if (= (% i 3) 0)
                                                                              (glm.vec4 0.6 0.3 0.9 1)
                                                                              (glm.vec4 0.2 0.6 0.9 1))}) 0)]}))
    (table.insert rows (NextFlex.FlexChild row 0)))
  (NextFlex.Flex {:name "profile-root"
                  :axis :y
                  :gap 0.01
                  :children rows}))

(fn run-profile []
  (local root (build-profile-tree))
  (for [frame 1 360]
    (NextLayout.run-frame root 2.6 2.1 0)
    (when (= (% frame 20) 0)
      (each [i row (ipairs root.children)]
        (local toggle (. row.children 1))
        (local progress (. row.children 2))
        (when (and toggle toggle.toggle)
          (toggle:toggle))
        (when (and progress progress.set-value)
          (progress:set-value (/ (% (+ frame i) 10) 10)))))))

(profiler.start)
(local call-result (table.pack (xpcall run-profile debug.traceback)))
(local ok (. call-result 1))
(local err (. call-result 2))
(profiler.stop_and_flush)

(if ok
    (logging.info (.. "Next layout profile written to " output-path))
    (error err))

true

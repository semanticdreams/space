(global app {})
(local EngineModule (require :engine))
(local os os)
(local math math)
(local io io)
(local fs (require :fs))
(local table table)
(local debug debug)
(local package package)
(local string string)
(local logging (require :logging))
(local FlamegraphProfiler (require :flamegraph-profiler))
(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))

(var textures (require :textures))
(fn install-fake-renderers []
  (fn FakeRenderers []
    (fn consume-vector [vector]
      (when (and vector vector.length)
        (vector:length)))

    (fn draw-target [_self target]
      (when (and target target.get-triangle-vector)
        (consume-vector (target:get-triangle-vector))
        (each [_ vector (pairs (target:get-text-vectors))]
          (consume-vector vector))))

    (fn update [self]
      (when app.scene
        (self:draw-target app.scene))
      (when app.hud
        (self:draw-target app.hud)))

    {:update update
     :draw-target draw-target
     :on-viewport-changed (fn [_ _] nil)
     :drop (fn [_] nil)})

  (set (. package.preload "renderers") (fn [] FakeRenderers))
  (set (. package.loaded "renderers") FakeRenderers))

(install-fake-renderers)
(fn install-fake-fxaa []
  (fn FakeFxaa []
    (var width 0)
    (var height 0)
    {:ready? (fn [_self] false)
     :get-fbo (fn [_self] 0)
     :get-depth-rbo (fn [_self] 0)
     :get-width (fn [_self] width)
     :get-height (fn [_self] height)
     :on-viewport-changed (fn [_self viewport]
                            (set width (math.max 0 (math.floor (or (and viewport viewport.width) 0))))
                            (set height (math.max 0 (math.floor (or (and viewport viewport.height) 0)))))
     :render (fn [_self] nil)
     :drop (fn [_self] nil)
     :set-enabled (fn [_self _] nil)
     :set-show-edges (fn [_self _] nil)
     :set-luma-threshold (fn [_self _] nil)
     :set-mul-reduce-reciprocal (fn [_self _] nil)
     :set-min-reduce-reciprocal (fn [_self _] nil)
     :set-max-span (fn [_self _] nil)})
  (set (. package.preload "fxaa") (fn [] FakeFxaa))
  (set (. package.loaded "fxaa") FakeFxaa))

(install-fake-fxaa)
(set app.disable_font_textures false)
(when (not textures)
  (set textures {}))
(when (not textures.load-texture-async)
  (local loaded {})
  (local stub
    (fn [name path]
      (local tex {:id (tonumber (tostring (string.byte name 1) 10))
                  :name name :path path
                  :ready true
                  :width 1
                  :height 1})
      (set (. loaded name) tex)
      tex))
  (set textures.load-texture stub)
  (set textures.load-texture-async stub))
(when (not textures.get-texture)
  (local loaded {})
  (set textures.get-texture
       (fn [_name]
         (error "textures.get_texture not implemented in graph profiler"))))
(when (not textures.load-cubemap)
  (local cube-stub (fn [_files] {:id 1 :ready true}))
  (set textures.load-cubemap cube-stub)
  (set textures.load-cubemap-async cube-stub))

(local MockOpenGL (require :mock-opengl))
(local global-mock (MockOpenGL))
(global-mock:install)

(set app.engine (EngineModule.Engine {:headless true}))

(local _ (require :main))

(app.engine:start)

(set textures.load-texture
     (fn [name path]
       {:id (tonumber (tostring (string.byte name 1) 10))
        :name name :path path
        :ready true
        :width 1
        :height 1}))
(set textures.load-texture-async textures.load-texture)
(when (not textures.get-texture)
  (set textures.get-texture (fn [_name] (error "textures.get_texture not implemented in graph profiler"))))
(when (not textures.load-cubemap)
  (local cube-stub (fn [_files] {:id 1 :ready true}))
  (set textures.load-cubemap cube-stub)
  (set textures.load-cubemap-async cube-stub))

(local default-output-path "prof/graph-layout.folded")
(local viewport {:width 450 :height 680})
(local frame-delta (/ 1.0 60.0))
(local iterations (or (tonumber (os.getenv "SPACE_GRAPH_ITERATIONS")) 600))
(local node-count (or (tonumber (os.getenv "SPACE_GRAPH_NODE_COUNT")) 30))
(local drag-frame-count (or (tonumber (os.getenv "SPACE_GRAPH_DRAG_FRAMES")) 240))
(local drag-radius (or (tonumber (os.getenv "SPACE_GRAPH_DRAG_RADIUS")) 80))

(fn to-samples [seconds]
  (math.max 1 (math.floor (+ (* seconds 1000000.0) 0.5))))

(fn ensure-output-directory [path]
(when (and path fs fs.parent fs.create-dirs)
    (local parent (fs.parent path))
    (when (and parent (> (string.len parent) 0))
      (local (ok err) (pcall (fn [] (fs.create-dirs parent))))
      (when (not ok)
        (error (.. "Failed to create directory for " path ": " err))))))

(fn write-folded [path collapsed]
  (ensure-output-directory path)
  (local handle (assert (io.open path "w") (.. "Unable to open flamegraph output " path)))
  (each [stack seconds (pairs collapsed)]
    (handle:write (string.format "%s %d\n" stack (to-samples seconds))))
  (handle:close))

(fn StackProfiler [opts]
  (local options (or opts {}))
  (var output-path options.output-path)
  (var stack [])
  (var collapsed {})

  (fn push-label [label]
    (table.insert stack label))

  (fn pop-label []
    (if (> (# stack) 0)
        (table.remove stack)))

  (fn record [seconds]
    (when (> (# stack) 0)
      (local path (table.concat stack ";"))
      (rawset collapsed path (+ (or (rawget collapsed path) 0.0) seconds))))

  (fn measure [label cb]
    (push-label label)
    (local start (os.clock))
    (local call-result (table.pack (pcall cb)))
    (local ok (. call-result 1))
    (local result (. call-result 2))
    (record (- (os.clock) start))
    (pop-label)
    (if ok
        result
        (error result)))

  (fn begin-frame [dt]
    (push-label (string.format "frame(%.3f)" dt)))

  (fn end-frame []
    (pop-label))

  (fn flush []
    (when output-path
      (write-folded output-path collapsed))
    collapsed)

  {:measure measure
   :begin-frame begin-frame
   :end-frame end-frame
   :flush flush
   :set_enabled (fn [_value] nil)
   :set_threshold (fn [_ms] nil)
   :set_log_interval (fn [_frames] nil)
   :set_output_path (fn [path] (set output-path path))})

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
  (logging.info "SPACE_FENNEL_FLAMEGRAPH disabled; not recording graph layout profile.")
  (os.exit 0))

(local profiler (FlamegraphProfiler {:output-path output-path}))

(fn emit-initial-viewport []
  (local payload {:width viewport.width :height viewport.height :timestamp 0})
  (if (and app.engine.events app.engine.events.window-resized)
      (app.engine.events.window-resized.emit payload)
      (do
        (app.set-viewport {:width viewport.width :height viewport.height})
        (app.reset-projection))))

(fn seed-graph [graph]
  (assert graph "seed-graph requires app.graph")
  (local nodes [])
  (local radius 180.0)
  (var i 1)
  (while (<= i node-count)
    (local angle (* 2 math.pi (/ i (math.max 1 node-count))))
    (local node (GraphNode {:key (.. "prof-node-" i)
                            :label (.. "Prof Node " i)}))
    (graph:add-node node {:position (glm.vec3 (* (math.cos angle) radius)
                                              (* (math.sin angle) radius)
                                              0)})
    (table.insert nodes node)
    (set i (+ i 1)))
  (var j 1)
  (while (<= j node-count)
    (local source (. nodes j))
    (local target (. nodes (if (= j node-count) 1 (+ j 1))))
    (when (and source target)
      (graph:add-edge (GraphEdge {:source source :target target})))
    (set j (+ j 1)))
  (var k 1)
  (while (<= k (- node-count 2))
    (local source (. nodes k))
    (local target (. nodes (+ k 2)))
    (when (and source target)
      (graph:add-edge (GraphEdge {:source source :target target})))
    (set k (+ k 1)))
  nodes)

(fn warmup-frames [count]
  (var i 1)
  (while (<= i count)
    (when app.graph-view
      (app.graph-view:update frame-delta))
    (set i (+ i 1))))

(fn run-force-layout [count]
  (when app.graph-view
    (app.graph-view:start-layout))
  (var i 1)
  (while (<= i count)
    (when app.graph-view
      (app.graph-view:update frame-delta))
    (set i (+ i 1))))

(fn find-graph-node-entry []
  (var found nil)
  (each [_ entry (ipairs (or app.movables.entries []))]
    (local node (and entry entry.key))
    (when (and (not found)
               node
               node.graph
               entry.target
               entry.target.set-position)
      (set found entry)))
  found)

(fn run-drag-loop [entry]
  (assert entry "run-drag-loop requires a movable entry")
  (local target entry.target)
  (local base (or target.position (glm.vec3 0 0 0)))
  (var step 1)
  (while (<= step drag-frame-count)
    (local angle (* 2 math.pi (/ step (math.max 1 drag-frame-count))))
    (local next-pos (glm.vec3 (+ base.x (* (math.cos angle) drag-radius))
                              (+ base.y (* (math.sin angle) drag-radius))
                              base.z))
    (target:set-position next-pos)
    (when app.graph-view
      (app.graph-view:update frame-delta))
    (set step (+ step 1))))

(fn profile-graph-layout []
  (app.init)
  (emit-initial-viewport)
  (seed-graph app.graph)
  (warmup-frames 30)
  (profiler.start)
  (run-force-layout iterations)
  (local entry (find-graph-node-entry))
  (when entry
    (run-drag-loop entry))
  (profiler.stop_and_flush)
  (app.drop))

(local profile-result (table.pack (xpcall profile-graph-layout debug.traceback)))
(local ok (. profile-result 1))
(local err (. profile-result 2))
(when (not ok)
  (app.drop)
  (app.engine:shutdown)
  (error err))

(app.engine:shutdown)
(logging.info (.. "Graph layout profile written to " output-path))

true

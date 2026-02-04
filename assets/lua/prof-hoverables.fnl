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

(local MockOpenGL (require :mock-opengl))
(local global-mock (MockOpenGL))
(local textures (require :textures))
(global-mock:install)

(set app.engine (EngineModule.Engine {:headless true}))
(set app.engine.get-asset-path (fn [path] (.. "assets/" path)))
(set app.disable_font_textures false)
(local default-output-path "prof/hoverables.folded")
(local frame-delta (/ 1.0 60.0))
(local iterations (or (tonumber (os.getenv "SPACE_HOVER_ITERATIONS")) 600))

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
  (logging.info "SPACE_FENNEL_FLAMEGRAPH disabled; not recording hoverables profile.")
  (os.exit 0))

(when (not textures)
  (set textures {}))
(local stub-texture
  (fn [name path]
    {:id (tonumber (tostring (string.byte name 1) 10))
     :name name :path path
     :ready true
     :width 1
     :height 1}))
(set textures.load-texture stub-texture)
(set textures.load-texture-async stub-texture)
(when (not textures.get-texture)
  (set textures.get-texture (fn [_name] (error "textures.get_texture not implemented in hoverables profiler"))))
(local cube-stub (fn [_files] {:id 1 :ready true}))
(set textures.load-cubemap cube-stub)
(set textures.load-cubemap-async cube-stub)

(local _ (require :main))

(app.engine:start)

(local profiler (FlamegraphProfiler {:output-path output-path}))

(fn profile-hoverables []
  (app.init)
  (set app.profiler nil)
  (profiler.start)
  (for [i 1 iterations]
    (app.update frame-delta))
  (profiler.stop_and_flush)
  (when (and app.engine app.drop)
    (app.drop)))

(local profile-result (table.pack (xpcall profile-hoverables debug.traceback)))
(local ok (. profile-result 1))
(local err (. profile-result 2))
(when (not ok)
  (when (and app.engine app.drop)
    (app.drop))
  (app.engine:shutdown)
  (error err))

(app.engine:shutdown)
(logging.info (.. "Hoverables profile written to " output-path))

true

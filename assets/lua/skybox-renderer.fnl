(local glm (require :glm))
(local fs (require :fs))
(local gl (require :gl))
(local shaders (require :shaders))
(local textures (require :textures))
(local SkyboxState (require :skybox-state))

(local unit-cube
  [-1.0 1.0 -1.0   -1.0 -1.0 -1.0    1.0 -1.0 -1.0
    1.0 -1.0 -1.0   1.0 1.0 -1.0     -1.0 1.0 -1.0

   -1.0 -1.0 1.0   -1.0 -1.0 -1.0   -1.0 1.0 -1.0
   -1.0 1.0 -1.0   -1.0 1.0 1.0     -1.0 -1.0 1.0

    1.0 -1.0 -1.0   1.0 -1.0 1.0      1.0 1.0 1.0
    1.0 1.0 1.0     1.0 1.0 -1.0      1.0 -1.0 -1.0

   -1.0 -1.0 1.0   -1.0 1.0 1.0       1.0 1.0 1.0
    1.0 1.0 1.0     1.0 -1.0 1.0     -1.0 -1.0 1.0

   -1.0 1.0 -1.0    1.0 1.0 -1.0      1.0 1.0 1.0
    1.0 1.0 1.0    -1.0 1.0 1.0      -1.0 1.0 -1.0

   -1.0 -1.0 -1.0  -1.0 -1.0 1.0      1.0 -1.0 -1.0
    1.0 -1.0 -1.0  -1.0 -1.0 1.0      1.0 -1.0 1.0])

(local cube-scale 600.0)

(local cube-vertices
  (let [result []]
    (for [i 1 (length unit-cube)]
      (table.insert result (* cube-scale (. unit-cube i))))
    result))

(local face-order ["right" "left" "top" "bottom" "back" "front"])

(fn ensure-directory [path]
  (when path
    (if (fs.exists path)
        (let [info (fs.stat path)]
          (if info.is-dir
              info.path
              info.parent))
        (and app.engine app.engine.get-asset-path
             (ensure-directory (app.engine.get-asset-path path))))))

(fn collect-face-files [folder]
  (local entries (fs.list-dir folder))
  (local lookup {})
  (each [_ entry (pairs entries)]
    (when (= entry.type "file")
      (set (. lookup entry.stem) entry.path)))
  (local files [])
  (for [i 1 (length face-order)]
    (local name (. face-order i))
    (local file (. lookup name))
    (assert file (.. "Missing skybox face '" name "' in " folder))
    (table.insert files file))
  files)

(fn SkyboxRenderer [opts]
  (local options (or opts {}))
  (local shader
    (shaders.load-shader-from-files
      "skybox"
      (app.engine.get-asset-path "shaders/skybox.vert")
      (app.engine.get-asset-path "shaders/skybox.frag")))

  (shader:use)
  (shader:setInteger "skybox" 0)

  (local vao (gl.glGenVertexArrays 1))
  (local vbo (gl.glGenBuffers 1))

  (gl.glBindVertexArray vao)
  (gl.glBindBuffer gl.GL_ARRAY_BUFFER vbo)
  (gl.glBufferData gl.GL_ARRAY_BUFFER cube-vertices gl.GL_STATIC_DRAW)
  (gl.glEnableVertexAttribArray 0)
  (gl.glVertexAttribPointer 0 3 gl.GL_FLOAT gl.GL_FALSE (* 3 4) 0)

  (var cubemap nil)
  (var state
       (SkyboxState.resolve-for-theme
         (SkyboxState.default-state)
         nil))
  (fn set-skybox-path [path]
    (when cubemap
      (cubemap:drop)
      (set cubemap nil))
    (if (not path)
        nil
        (do
          (local folder (ensure-directory path))
          (assert folder (.. "Skybox path not found: " (or path "<nil>")))
          (assert (and textures (or textures.load-cubemap textures.load-cubemap-async))
                  "Cubemap textures are unavailable")
          (local files (collect-face-files folder))
          (local loader (or textures.load-cubemap-async textures.load-cubemap))
          (set cubemap (loader files)))))

  (fn set-state [self next-state]
    (local normalized
      (SkyboxState.normalize-resolved-state next-state "SkyboxRenderer.set-state"))
    (local path-changed?
      (or (not (= normalized.enabled? state.enabled?))
          (not (= normalized.name state.name))))
    (set state normalized)
    (when path-changed?
      (if normalized.enabled?
          (set-skybox-path (SkyboxState.asset-path normalized))
          (set-skybox-path nil)))
    normalized)

  (fn get-state [_self]
    (SkyboxState.clone-state state))

  (fn render [self target]
    (when (and state.enabled?
               cubemap
               (or (not cubemap.ready) cubemap.ready)
               target
               target.projection
               target.get-view-matrix)
      (gl.glDepthMask gl.GL_FALSE)
      (gl.glBindVertexArray vao)
      (shader:use)
      (shader:setFloat "brightness" state.brightness)
      (local tint-color (or (. state :tint-color) [1.0 1.0 1.0]))
      (shader:setVector3f "tintColor"
                          (. tint-color 1)
                          (. tint-color 2)
                          (. tint-color 3))
      (shader:setMatrix4 "projection" target.projection)
      (local view (target:get-view-matrix))
      (local view-rotation (glm.strip-translation view))
      (shader:setMatrix4 "view" view-rotation)
      (gl.glActiveTexture gl.GL_TEXTURE0)
      (gl.glBindTexture gl.GL_TEXTURE_CUBE_MAP cubemap.id)
      (gl.glDrawArrays gl.GL_TRIANGLES 0 36)
      (gl.glDepthMask gl.GL_TRUE)))

  (fn drop [_self]
    (when cubemap
      (cubemap:drop)
      (set cubemap nil)))

  (local api {:shader shader})
  (set api.render render)
  (set api.set-state set-state)
  (set api.get-state get-state)
  (set api.drop drop)
  (api:set-state (or options.state (SkyboxState.default-state)))
  api)

SkyboxRenderer

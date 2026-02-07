(local glm (require :glm))
(local fs (require :fs))
(local gl (require :gl))
(local shaders (require :shaders))
(local textures (require :textures))

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
  (var active false)
  (var brightness (or options.brightness 1.0))
  (fn set-skybox [self path]
    (when cubemap
      (cubemap:drop)
      (set cubemap nil))
    (if (not path)
        (set active false)
        (let [folder (ensure-directory path)]
          (assert folder (.. "Skybox path not found: " (or path "<nil>")))
          (assert (and textures (or textures.load-cubemap textures.load-cubemap-async))
                  "Cubemap textures are unavailable")
          (local files (collect-face-files folder))
          (local loader (or textures.load-cubemap-async textures.load-cubemap))
          (set cubemap (loader files))
          (set active true))))

  (fn set-brightness [self value]
    (assert (= (type value) "number") "Skybox brightness requires a numeric value")
    (set brightness value))

  (fn render [self target]
    (when (and active cubemap (or (not cubemap.ready) cubemap.ready) target target.projection target.get-view-matrix)
      (gl.glDepthMask gl.GL_FALSE)
      (gl.glBindVertexArray vao)
      (shader:use)
      (shader:setFloat "brightness" brightness)
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
  (set api.set-skybox set-skybox)
  (set api.set-brightness set-brightness)
  (set api.drop drop)
  (local default-path (or options.path "skyboxes/lake"))
  (api:set-skybox default-path)
  api)

SkyboxRenderer

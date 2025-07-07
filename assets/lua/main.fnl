(local fennel (require :fennel))
(fn _G.pp [x] (print (fennel.view x)))

;(local test (require :test))
;(test.hello)

(local sqlite (require :lsqlite3))

(fn space.init []
  (local db_path (space.join_path space.data_dir "space.db"))
  (local db (sqlite.open db_path))
  (print "fennel init"))

(fn space.update [delta]
  (gl.glBindFramebuffer gl.GL_FRAMEBUFFER space.fbo)
  (gl.glEnable gl.GL_DEPTH_TEST)
  (gl.glDepthFunc gl.GL_LESS)
  (gl.glClearColor 1.0 0.5 0.0 1.0)
  (gl.glClear (bor gl.GL_COLOR_BUFFER_BIT gl.GL_DEPTH_BUFFER_BIT))
)

(fn space.drop []
  (print "fennel drop"))

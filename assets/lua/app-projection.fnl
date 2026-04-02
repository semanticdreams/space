(local glm (require :glm))
(local viewport-utils (require :viewport-utils))

(fn create-default-projection [viewport-data]
  (local viewport (viewport-utils.to-table (or viewport-data
                                              (and app app.viewport))))
  (local width (math.max 1 (or (and viewport viewport.width) 1)))
  (local height (math.max 1 (or (and viewport viewport.height) 1)))
  (local aspect (/ width height))
  (glm.perspective 0.7853982 aspect 1.0 10000.0))

{:create-default-projection create-default-projection}

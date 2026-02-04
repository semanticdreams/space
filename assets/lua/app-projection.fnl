(local glm (require :glm))

(fn create-default-projection []
  (glm.perspective -5.0 2.0 10 2000.0))

{:create-default-projection create-default-projection}

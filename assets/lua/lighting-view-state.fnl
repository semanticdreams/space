(local glm (require :glm))

(local perspective-uniform-mode 0)
(local orthographic-uniform-mode 1)

(fn assert-vec3 [value context]
  (assert value (.. context " requires glm.vec3"))
  (assert (and (not (= value.x nil))
               (not (= value.y nil))
               (not (= value.z nil)))
          (.. context " requires glm.vec3"))
  value)

(fn require-direction [value context]
  (local direction (assert-vec3 value context))
  (assert (> (glm.length direction) 1e-6)
          (.. context " requires non-zero direction"))
  direction)

(fn normalize-direction [value context]
  (local direction (require-direction value context))
  (glm.normalize direction))

(fn perspective [position]
  {:kind :perspective
   :position (assert-vec3 position "LightingViewState.perspective")})

(fn orthographic [direction]
  {:kind :orthographic
   :direction (normalize-direction direction "LightingViewState.orthographic")})

(fn normalize-state [state context]
  (local resolved-context (or context "LightingViewState"))
  (assert (= (type state) :table)
          (.. resolved-context " requires a lighting view state table"))
  (local kind state.kind)
  (if (= kind :perspective)
      (do
        (assert-vec3 state.position
                     (.. resolved-context " perspective state"))
        state)
      (= kind :orthographic)
      (do
        (local direction
          (require-direction state.direction
                             (.. resolved-context " orthographic state")))
        (if (< (math.abs (- (glm.length direction) 1.0)) 1e-6)
            state
            {:kind :orthographic
             :direction (glm.normalize direction)}))
      (error (.. resolved-context
                  " requires :kind of :perspective or :orthographic"))))

(fn validate-state [state context]
  (local resolved-context (or context "LightingViewState"))
  (assert (= (type state) :table)
          (.. resolved-context " requires a lighting view state table"))
  (local kind state.kind)
  (if (= kind :perspective)
      (do
        (assert-vec3 state.position
                     (.. resolved-context " perspective state"))
        state)
      (= kind :orthographic)
      (do
        (require-direction state.direction
                           (.. resolved-context " orthographic state"))
        state)
      (error (.. resolved-context
                  " requires :kind of :perspective or :orthographic"))))

(fn apply-uniforms [shader state]
  (local resolved (validate-state state "LightingViewState.apply-uniforms"))
  (if (= resolved.kind :perspective)
      (do
        (shader:setInteger "lightingViewMode" perspective-uniform-mode)
        (shader:setVector3f "lightingViewPos"
                            resolved.position.x
                            resolved.position.y
                            resolved.position.z)
        (shader:setVector3f "lightingViewDir" 0.0 0.0 0.0))
      (do
        (shader:setInteger "lightingViewMode" orthographic-uniform-mode)
        (shader:setVector3f "lightingViewPos" 0.0 0.0 0.0)
        (shader:setVector3f "lightingViewDir"
                            resolved.direction.x
                            resolved.direction.y
                            resolved.direction.z)))
  resolved)

{:perspective perspective
 :orthographic orthographic
 :normalize-state normalize-state
 :validate-state validate-state
 :apply-uniforms apply-uniforms
 :perspective-uniform-mode perspective-uniform-mode
 :orthographic-uniform-mode orthographic-uniform-mode}

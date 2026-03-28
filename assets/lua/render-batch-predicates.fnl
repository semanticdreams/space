(fn vector-has-elements? [vector]
  (and vector (> (vector:length) 0)))

(fn renderable-mesh-batch? [batch]
  (and batch
       (not (= batch.visible? false))
       (vector-has-elements? batch.vector)))

(fn lit-mesh-batch? [batch]
  (and (renderable-mesh-batch? batch)
       (not batch.unlit)))

(fn mesh-batches-require-lighting? [batches]
  (accumulate [required? false _ batch (ipairs (or batches []))]
    (or required? (lit-mesh-batch? batch))))

(fn renderable-instanced-color-mesh-batch? [batch]
  (and batch
       (not (= batch.visible? false))
       (vector-has-elements? batch.vertex-vector)
       (vector-has-elements? batch.instance-vector)))

(fn lit-instanced-color-mesh-batch? [batch]
  (and (renderable-instanced-color-mesh-batch? batch)
       (not batch.unlit)))

(fn instanced-color-mesh-batches-require-lighting? [batches]
  (accumulate [required? false _ batch (ipairs (or batches []))]
    (or required? (lit-instanced-color-mesh-batch? batch))))

(fn renderable-quad-draw-entry? [entry]
  (and entry
       entry.vector
       entry.batches
       entry.clip-vector
       entry.clip-group-vector
       (vector-has-elements? entry.vector)))

{:vector-has-elements? vector-has-elements?
 :renderable-mesh-batch? renderable-mesh-batch?
 :lit-mesh-batch? lit-mesh-batch?
 :mesh-batches-require-lighting? mesh-batches-require-lighting?
 :renderable-instanced-color-mesh-batch? renderable-instanced-color-mesh-batch?
 :lit-instanced-color-mesh-batch? lit-instanced-color-mesh-batch?
 :instanced-color-mesh-batches-require-lighting? instanced-color-mesh-batches-require-lighting?
 :renderable-quad-draw-entry? renderable-quad-draw-entry?}

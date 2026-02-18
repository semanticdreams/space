(local Text (require :text))
(local Utils (require :graph/view/utils))

(fn DefaultNodePreview [node opts]
  (local options (or opts {}))
  (local target (or node options.node))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "DefaultNodePreview requires a build context")
    (local label (or (and target target.label)
                     (and target target.key)
                     "node"))
    ((Text {:text (Utils.truncate-with-ellipsis (tostring label) 60)})
     build-ctx)))

DefaultNodePreview

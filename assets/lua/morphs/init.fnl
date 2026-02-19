(local Signal (require :signal))

(local M {})

(fn key-scheme [key]
  (when (and key (= (type key) "string"))
    (local (start _end) (string.find key ":" 1 true))
    (if start
        (string.sub key 1 (- start 1))
        key)))

(fn is-identity-key? [key]
  (and (= (type key) "string")
       (= (string.sub key 1 9) "identity:")))

(fn normalize-source-node [source-node]
  (if (and source-node source-node.key)
      source-node
      nil))

(fn default-target-label [scheme]
  (tostring (or scheme "")))

(fn Morphs [opts]
  (local options (or opts {}))
  (local registry {})
  (local morphed (Signal))

  (fn register [self from-scheme to-scheme morph-fn meta]
    (assert from-scheme "Morphs.register requires from-scheme")
    (assert to-scheme "Morphs.register requires to-scheme")
    (assert (= (type morph-fn) "function") "Morphs.register requires morph function")
    (var from-map (. registry from-scheme))
    (when (not from-map)
      (set from-map {})
      (set (. registry from-scheme) from-map))
    (set (. from-map to-scheme) {:run morph-fn
                                 :label (or (and meta meta.label) (default-target-label to-scheme))
                                 :to-scheme to-scheme})
    true)

  (fn target-items [_self source-node]
    (local source (normalize-source-node source-node))
    (if (or (not source) (is-identity-key? source.key))
        []
        (do
          (local from-scheme (key-scheme source.key))
          (local from-map (. registry from-scheme))
          (if (not from-map)
              []
              (do
                (local items [])
                (each [to-scheme spec (pairs from-map)]
                  (table.insert items [{:to-scheme to-scheme
                                        :label spec.label}
                                       spec.label]))
                (table.sort items
                            (fn [a b]
                              (< (tostring (. a 2)) (tostring (. b 2)))))
                items)))))

  (fn apply [self source-node target opts]
    (local source (normalize-source-node source-node))
    (assert source "Morphs.apply requires a source node")
    (assert source.key "Morphs.apply requires source node key")
    (assert (not (is-identity-key? source.key)) "Identity nodes are not morphable")
    (local to-scheme
      (if (= (type target) "table")
          (or target.to-scheme target.scheme target.key)
          target))
    (assert to-scheme "Morphs.apply requires target scheme")
    (local from-scheme (key-scheme source.key))
    (local from-map (. registry from-scheme))
    (assert from-map (.. "No morphs registered for source scheme: " (tostring from-scheme)))
    (local spec (. from-map to-scheme))
    (assert spec (.. "No morph registered: " (tostring from-scheme) " -> " (tostring to-scheme)))
    (local result (spec.run {:source-node source
                             :options (or opts {})}))
    (morphed:emit {:source-node source
                   :source-key source.key
                   :from-scheme from-scheme
                   :to-scheme to-scheme
                   :result result})
    result)

  {:register register
   :target-items target-items
   :apply apply
   :morphed morphed
   :registry registry})

(var default-morphs nil)

(fn get-default [opts]
  (if default-morphs
      default-morphs
      (do
        (set default-morphs (Morphs (or opts {})))
        (local register-defaults (require :morphs/string-entity-to-code-entity))
        (register-defaults default-morphs)
        default-morphs)))

(set M.Morphs Morphs)
(set M.get-default get-default)
(set M.key-scheme key-scheme)
(set M.is-identity-key? is-identity-key?)

M

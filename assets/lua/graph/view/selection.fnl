(local Signal (require :signal))
(local logging (require :logging))

(fn selections-equal? [a b]
    (if (not (= (length a) (length b)))
        false
        (do
            (var mismatch false)
            (each [_ item (ipairs a)]
                (var found false)
                (each [_ other (ipairs b)]
                    (when (= item other)
                        (set found true)))
                (when (not found)
                    (set mismatch true)))
            (not mismatch))))

(fn replace-contents [target source]
    (for [i (length target) 1 -1]
        (table.remove target i))
    (each [_ item (ipairs (or source []))]
        (table.insert target item)))

(fn GraphViewSelection [opts]
    (local options (or opts {}))
    (local selector options.selector)
    (local node-by-point (or options.node-by-point {}))
    (local selected-nodes (or options.selected-nodes []))
    (local selected-nodes-changed (or options.selected-nodes-changed (Signal)))
    (local on-change options.on-change)
    (local node-id (or options.node-id (fn [node] (or node.label node.key "<unknown>"))))
    (var selector-handler nil)
    (var selection nil)

    (fn log-selected []
        (local labels
          (icollect [_ node (ipairs selected-nodes)]
                    (or node.label (node-id node))))
        (local label-str (if (> (length labels) 0)
                             (table.concat labels ", ")
                             "none"))
        (logging.info (string.format "[graph-view] selected nodes: %s" label-str)))

    (fn emit-change []
        (selected-nodes-changed:emit selected-nodes)
        (log-selected)
        (when on-change
            (on-change selected-nodes)))

    (fn set-selection [_self nodes]
        (when (not (selections-equal? nodes selected-nodes))
            (replace-contents selected-nodes nodes)
            (emit-change)))

    (fn resolve-selection []
        (local resolved [])
        (when selector
            (each [_ point (ipairs selector.selected)]
                (local node (. node-by-point point))
                (when node
                    (table.insert resolved node))))
        resolved)

    (fn on-selection-changed [_self]
        (set-selection selection (resolve-selection)))

    (fn prune [_self removed]
        (local remaining [])
        (each [_ node (ipairs selected-nodes)]
            (when (not (rawget removed node))
                (table.insert remaining node)))
        (set-selection selection remaining))

    (fn drop [_self]
        (when (and selector selector.changed selector-handler)
            (selector.changed:disconnect selector-handler true)
            (set selector-handler nil)))

    (fn attach [_self]
        (when (and selector selector.changed (not selector-handler))
            (set selector-handler
                 (selector.changed:connect (fn [_] (on-selection-changed selection))))))

    (set selection {:selected-nodes selected-nodes
                    :selected-nodes-changed selected-nodes-changed
                    :set-selection set-selection
                    :resolve-selection resolve-selection
                    :on-selection-changed on-selection-changed
                    :prune prune
                    :attach attach
                    :drop drop})
    selection)

GraphViewSelection

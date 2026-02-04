(local glm (require :glm))
(local Utils (require :graph/view/utils))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local fs (require :fs))

(local ensure-glm-vec3 Utils.ensure-glm-vec3)
(local position-magnitude-threshold 1e6)

(fn GraphViewPersistence [opts]
    (local options (or opts {}))
    (local data-dir options.data-dir)
    (assert data-dir "GraphViewPersistence requires data-dir")
    (local graph-data-dir (fs.join-path data-dir "graph-view"))
    (local metadata-path (fs.join-path graph-data-dir "metadata.json"))
    (var pending-save? false)
    (var persisted {:positions {}})
    (var persisted-positions persisted.positions)

    (fn finite-number? [value]
        (and (= (type value) :number)
             (= value value)
             (not (= value math.huge))
             (not (= value (- math.huge)))))

    (fn assert-valid-position [key value context]
        (local prefix (or context "GraphViewPersistence position"))
        (assert (= (type value) :table)
                (string.format "%s for %s must be a table" prefix key))
        (assert (finite-number? (rawget value 1))
                (string.format "%s for %s has invalid x value" prefix key))
        (assert (finite-number? (rawget value 2))
                (string.format "%s for %s has invalid y value" prefix key))
        (assert (finite-number? (rawget value 3))
                (string.format "%s for %s has invalid z value" prefix key))
        (local magnitude (glm.length (ensure-glm-vec3 value)))
        (assert (<= magnitude position-magnitude-threshold)
                (string.format "%s for %s magnitude %.3f exceeds threshold %.0f"
                               prefix
                               key
                               magnitude
                               position-magnitude-threshold)))

    (fn ensure-graph-data-dir []
        (local (ok result) (pcall fs.create-dirs graph-data-dir))
        (when (not ok)
            (error (string.format "GraphView failed to create %s: %s"
                                  graph-data-dir
                                  result)))
        true)

    (fn load []
        (ensure-graph-data-dir)
        (when (fs.exists metadata-path)
            (local (read-ok content) (pcall fs.read-file metadata-path))
            (when (not read-ok)
                (error (string.format "GraphView failed to read %s: %s"
                                      metadata-path
                                      content)))
            (local (parse-ok decoded) (pcall json.loads content))
            (when (not parse-ok)
                (error (string.format "GraphView failed to parse %s: %s"
                                      metadata-path
                                      decoded)))
            (local positions (or decoded.positions {}))
            (each [key value (pairs positions)]
                (assert-valid-position key value "GraphViewPersistence load"))
            (set persisted {:positions positions})
            (set persisted-positions positions)))

    (fn saved-position [_self node]
        (when (and node node.key)
            (local stored (. persisted-positions node.key))
            (when stored
                (assert-valid-position node.key stored "GraphViewPersistence saved-position")
                (ensure-glm-vec3 stored))))

    (fn capture-positions [_self points]
        (local positions {})
        (each [node point (pairs points)]
            (when (and node node.key point point.position)
                (local pos point.position)
                (assert (finite-number? pos.x)
                        (string.format "GraphViewPersistence capture has invalid x for %s" node.key))
                (assert (finite-number? pos.y)
                        (string.format "GraphViewPersistence capture has invalid y for %s" node.key))
                (assert (finite-number? pos.z)
                        (string.format "GraphViewPersistence capture has invalid z for %s" node.key))
                (local magnitude (glm.length pos))
                (assert (<= magnitude position-magnitude-threshold)
                        (string.format "GraphViewPersistence capture magnitude %.3f exceeds threshold %.0f for %s"
                                       magnitude
                                       position-magnitude-threshold
                                       node.key))
                (tset positions node.key [pos.x pos.y pos.z])))
        positions)

    (fn persist [self points force?]
        (when (or pending-save? force?)
            (ensure-graph-data-dir)
            (local positions (self:capture-positions points))
            (local merged {})
            (when persisted-positions
                (each [k v (pairs persisted-positions)]
                    (tset merged k v)))
            (each [k v (pairs positions)]
                (tset merged k v))
            (set persisted.positions merged)
            (local (write-ok err) (pcall (fn [] (JsonUtils.write-json! metadata-path persisted))))
            (when (not write-ok)
                (error (string.format "GraphView failed to write %s: %s"
                                      metadata-path
                                      err)))
            (set persisted-positions merged)
            (set pending-save? false)))

    (fn schedule-save [_self]
        (set pending-save? true))

    (local self {:load load
                 :persist persist
                 :schedule-save schedule-save
                 :saved-position saved-position
                 :capture-positions capture-positions
                 :metadata-path metadata-path})

    (self:load)
    self)

GraphViewPersistence

(local Boundary (require :activity-surface-boundary))

(local tests [])

(fn snapshot-app-fields [keys]
  (local snapshot {:keys keys
                   :values {}})
  (each [_ key (ipairs keys)]
    (set (. snapshot.values key) (. app key)))
  snapshot)

(fn restore-app-fields! [snapshot]
  (each [_ key (ipairs snapshot.keys)]
    (set (. app key) (. snapshot.values key)))
  true)

(fn with-boundary-app [fields f]
  (local snapshot (snapshot-app-fields [:active-activity-id
                                        :activity-registry
                                        :active-world-runtime]))
  (set app.active-activity-id fields.active-activity-id)
  (set app.activity-registry fields.activity-registry)
  (set app.active-world-runtime fields.active-world-runtime)
  (local (ok result) (pcall f))
  (restore-app-fields! snapshot)
  (if ok
      result
      (error result)))

(fn expect-foreign-slot-denied []
  (Boundary.assert-slot-owner! :canvas "set-camera" "graph" {}))

(fn expect-empty-direct-ray-denied []
  (Boundary.assert-screen-ray-authorized! :canvas "screen-pos-ray" {} nil))

(fn assert-error-contains [err fragments]
  (local message (tostring err))
  (each [_ fragment (ipairs fragments)]
    (assert (string.find message fragment 1 true)
            (.. "Expected error to contain `" fragment "`, got: " message))))

(fn matching-owner-can-mutate-slot []
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (assert (= (Boundary.assert-slot-owner! :canvas "set-camera" "bubbles" {}) true)))))

(fn foreign-owner-cannot-mutate-slot []
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (local (ok err) (pcall expect-foreign-slot-denied))
      (assert (not ok) "Foreign activity slot mutation must fail")
      (assert-error-contains err ["activity surface boundary denied"
                                  "canvas"
                                  "set-camera"
                                  "graph"
                                  "bubbles"]))))

(fn explicit-matrix-ray-opts-are-authorized []
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (assert (= (Boundary.assert-screen-ray-authorized! :canvas "screen-pos-ray"
                                                         {:view :view-matrix
                                                          :projection :projection-matrix}
                                                         nil)
                 true)))))

(fn empty-direct-ray-opts-fail-in-active-context []
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (local (ok err) (pcall expect-empty-direct-ray-denied))
      (assert (not ok) "Ambiguous direct ray must fail in active activity context")
      (assert-error-contains err ["ambiguous direct screen ray"
                                  "presentation target/helper"]))))

(fn active-activity-slot-authorizes-ray []
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (assert (= (Boundary.assert-screen-ray-authorized! :canvas "screen-pos-ray"
                                                         {:activity-slot {:activity-id "bubbles"}}
                                                         nil)
                 true)))))

(fn target-ownership-requires-active-slot-in-active-context []
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (assert (Boundary.target-owned-by-active? {:kind :hud})
              "Non-scene/canvas targets without slots should stay authorized")
      (assert (Boundary.target-owned-by-active? {:kind :canvas
                                                :slot {:activity-id "bubbles"}})
              "Scene/canvas targets owned by the active slot should be authorized")
      (assert (not (Boundary.target-owned-by-active? {:kind :canvas}))
              "Scene/canvas targets without slots should not be active-owned")
      (assert (not (Boundary.target-owned-by-active? {:kind :scene
                                                     :slot {:activity-id "graph"}}))
              "Foreign scene/canvas targets should not be active-owned"))))

(fn deactivate-foreign-slots-preserves-active-slot []
  (local calls [])
  (local bubbles-slot {:activity-id "bubbles"
                       :visible? true
                       :interactive? true})
  (local graph-slot {:activity-id "graph"
                     :visible? true
                     :interactive? true})
  (local surface
    {:activity-slots {:bubbles bubbles-slot
                      :graph graph-slot}
     :active-activity-slot graph-slot
     :active-activity-slot-id "graph"
     :deactivate-activity-slot (fn [self activity-id opts]
                                 (table.insert calls {:activity-id activity-id
                                                      :opts opts})
                                 (local slot (. self.activity-slots activity-id))
                                 (when slot
                                   (set slot.visible? false)
                                   (set slot.interactive? false))
                                 slot)})
  (local count (Boundary.deactivate-foreign-slots! surface "bubbles"))
  (assert (= count 1))
  (assert (= (length calls) 1))
  (assert (= (. (. calls 1) :activity-id) "graph"))
  (assert (= (. (. (. calls 1) :opts) :boundary-internal?) true))
  (assert (not graph-slot.visible?))
  (assert (not graph-slot.interactive?))
  (assert bubbles-slot.visible?)
  (assert bubbles-slot.interactive?)
  (assert (= surface.active-activity-slot nil))
  (assert (= surface.active-activity-slot-id nil)))

(table.insert tests {:name "matching owner can mutate an activity slot"
                     :fn matching-owner-can-mutate-slot})
(table.insert tests {:name "foreign owner cannot mutate an activity slot"
                     :fn foreign-owner-cannot-mutate-slot})
(table.insert tests {:name "explicit matrix direct ray options are authorized"
                     :fn explicit-matrix-ray-opts-are-authorized})
(table.insert tests {:name "empty direct ray options fail in active contexts"
                     :fn empty-direct-ray-opts-fail-in-active-context})
(table.insert tests {:name "active activity slot authorizes a direct ray"
                     :fn active-activity-slot-authorizes-ray})
(table.insert tests {:name "target ownership requires active scene/canvas slots"
                     :fn target-ownership-requires-active-slot-in-active-context})
(table.insert tests {:name "deactivate foreign slots preserves the active slot"
                     :fn deactivate-foreign-slots-preserves-active-slot})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "activity-surface-boundary"
                       :tests tests})))

{:name "activity-surface-boundary"
 :tests tests
 :main main}

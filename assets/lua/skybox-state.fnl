(local fs (require :fs))

(local default-skybox-name "lake")
(local default-brightness 0.1)

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn default-state []
  {:enabled? true
   :name default-skybox-name
   :brightness default-brightness})

(fn normalize-complete-state [state context]
  (local label (or context "SkyboxState"))
  (assert (= (type state) :table) (.. label " requires skybox state table"))
  (assert (= (type state.enabled?) :boolean) (.. label " requires boolean :enabled?"))
  (assert (= (type state.name) :string) (.. label " requires string :name"))
  (assert (> (string.len state.name) 0) (.. label " requires non-empty :name"))
  (assert (= (type state.brightness) :number) (.. label " requires numeric :brightness"))
  {:enabled? state.enabled?
   :name state.name
   :brightness state.brightness})

(fn asset-path [state]
  (.. "skyboxes/" state.name))

(fn available-items [get-asset-path]
  (assert (= (type get-asset-path) :function)
          "SkyboxState.available-items requires get-asset-path function")
  (local skyboxes-dir (get-asset-path "skyboxes"))
  (assert skyboxes-dir "SkyboxState.available-items requires skyboxes asset directory")
  (assert (fs.exists skyboxes-dir)
          (.. "SkyboxState.available-items missing skyboxes directory: " skyboxes-dir))
  (local items [])
  (each [_ entry (ipairs (fs.list-dir skyboxes-dir))]
    (when (= entry.type "directory")
      (table.insert items [entry.name entry.name])))
  (table.sort items
              (fn [left right]
                (< (. left 1) (. right 1))))
  (assert (> (length items) 0)
          (.. "SkyboxState.available-items found no skyboxes in " skyboxes-dir))
  items)

{:default-state default-state
 :normalize-complete-state normalize-complete-state
 :asset-path asset-path
 :available-items available-items
 :clone-state clone-table}

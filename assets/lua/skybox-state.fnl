(local fs (require :fs))

(local default-skybox-name "lake")
(local default-brightness 0.1)
(local default-tint-color [1.0 1.0 1.0])

(fn clone-tint-color [value]
  [(. value 1) (. value 2) (. value 3)])

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn normalize-theme-key [value context]
  (if (= value nil)
      nil
      (do
        (local key (tostring value))
        (assert (> (string.len key) 0)
                (.. (or context "SkyboxState") " requires non-empty theme key"))
        key)))

(fn normalize-entry [state context]
  (local label (or context "SkyboxState"))
  (assert (= (type state) :table) (.. label " requires skybox entry table"))
  (assert (= (type state.name) :string) (.. label " requires string :name"))
  (assert (> (string.len state.name) 0) (.. label " requires non-empty :name"))
  (assert (= (type state.brightness) :number) (.. label " requires numeric :brightness"))
  (local tint-color (or (. state :tint-color) default-tint-color))
  (assert (= (type tint-color) :table) (.. label " requires table :tint-color"))
  (assert (= (length tint-color) 3) (.. label " requires :tint-color with 3 numbers"))
  (each [idx value (ipairs tint-color)]
    (assert (= (type value) :number)
            (.. label " requires numeric :tint-color[" (tostring idx) "]"))
    (assert (and (>= value 0.0) (<= value 1.0))
            (.. label
                " requires :tint-color["
                (tostring idx)
                "] between 0 and 1")))
  {:name state.name
   :brightness state.brightness
   :tint-color (clone-tint-color tint-color)})

(fn default-state []
  {:enabled? true
   :default {:name default-skybox-name
             :brightness default-brightness
             :tint-color (clone-tint-color default-tint-color)}
   :by-theme {}})

(fn normalize-complete-state [state context]
  (local label (or context "SkyboxState"))
  (assert (= (type state) :table) (.. label " requires skybox state table"))
  (assert (= (type state.enabled?) :boolean) (.. label " requires boolean :enabled?"))
  (if (and state.default (not (= state.name nil)))
      (error (.. label " must not mix :default with legacy :name/:brightness fields")))
  (if state.default
      (do
        (local by-theme {})
        (each [key value (pairs (or state.by-theme {}))]
          (local normalized-key
            (normalize-theme-key key (.. label " by-theme")))
          (set (. by-theme normalized-key)
               (normalize-entry value
                                (.. label " by-theme[" normalized-key "]"))))
        {:enabled? state.enabled?
         :default (normalize-entry state.default (.. label " default"))
         :by-theme by-theme})
      {:enabled? state.enabled?
       :default (normalize-entry state label)
       :by-theme {}}))

(fn normalize-resolved-state [state context]
  (local label (or context "SkyboxState"))
  (assert (= (type state) :table) (.. label " requires skybox state table"))
  (assert (= (type state.enabled?) :boolean) (.. label " requires boolean :enabled?"))
  (local entry
    (if state.default
        state.default
        state))
  (local normalized-entry (normalize-entry entry label))
  {:enabled? state.enabled?
   :name normalized-entry.name
   :brightness normalized-entry.brightness
   :tint-color normalized-entry.tint-color})

(fn resolve-for-theme [state theme-key]
  (local normalized
    (normalize-complete-state state "SkyboxState.resolve-for-theme"))
  (local key (normalize-theme-key theme-key "SkyboxState.resolve-for-theme"))
  (local entry
    (or (and key (. normalized.by-theme key))
        normalized.default))
  {:enabled? normalized.enabled?
   :name entry.name
   :brightness entry.brightness
   :tint-color entry.tint-color})

(fn asset-path [state]
  (local normalized
    (normalize-resolved-state state "SkyboxState.asset-path"))
  (.. "skyboxes/" normalized.name))

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
 :normalize-resolved-state normalize-resolved-state
 :normalize-theme-key normalize-theme-key
 :resolve-for-theme resolve-for-theme
 :asset-path asset-path
 :available-items available-items
 :clone-state clone-table}

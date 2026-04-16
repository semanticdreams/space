(local Padding (require :padding))
(local Text (require :text))
(local Button (require :button))
(local Input (require :input))
(local {: Flex : FlexChild} (require :flex))
(local FormComboBox (require :graph/view/widgets/form-combo-box))
(local SkyboxState (require :skybox-state))

(local bool-items
  [["true" "Enabled"]
   ["false" "Disabled"]])

(fn bool-text [value]
  (if (= value false) "false" "true"))

(fn parse-bool [text]
  (if (= text "true")
      true
      (if (= text "false")
          false
          nil)))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn item-value-set [items]
  (local lookup {})
  (each [_ item (ipairs (or items []))]
    (set (. lookup (tostring (. item 1))) true))
  lookup)

(fn theme-entries [target record]
  (local lookup {})
  (local ordered [])
  (each [_ item (ipairs (or ((assert target.available-themes
                                     "SkyboxNodeView requires target.available-themes")
                             target) []))]
    (local key (SkyboxState.normalize-theme-key
                 (. item 1)
                 "SkyboxNodeView theme key"))
    (local label (tostring (or (. item 2) key)))
    (when (not (. lookup key))
      (local entry {:key key :label label})
      (set (. lookup key) entry)
      (table.insert ordered entry)))
  (each [key _override (pairs (or record.by-theme {}))]
    (local normalized-key
      (SkyboxState.normalize-theme-key key "SkyboxNodeView theme override"))
    (when (not (. lookup normalized-key))
      (local entry {:key normalized-key
                    :label normalized-key
                    :unknown? true})
      (set (. lookup normalized-key) entry)
      (table.insert ordered entry)))
  (table.sort ordered
              (fn [left right]
                (< left.key right.key)))
  ordered)

(fn labeled-row [label-text field-builder]
  (Flex {:axis :x
         :xspacing 0.6
         :yalign :center
         :children [(FlexChild (Text {:text label-text}) 0)
                    (FlexChild field-builder 1)]}))

(fn theme-row [entry name-builder brightness-builder clear-builder]
  (Flex {:axis :x
         :xspacing 0.5
         :yalign :center
         :children [(FlexChild (Text {:text entry.label}) 0)
                    (FlexChild name-builder 1)
                    (FlexChild brightness-builder 0)
                    (FlexChild clear-builder 0)]}))

(fn info-text [target]
  (.. "Editing world skybox policy for "
      (or (and target target.world-id) "?")))

(fn SkyboxNodeView [node opts]
  (local options (or opts {}))
  (local target (assert (or node options.node) "SkyboxNodeView requires target node"))
  (local skybox-items
    ((assert target.available-items "SkyboxNodeView requires target.available-items")
     target))
  (local allowed-skyboxes (item-value-set skybox-items))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "SkyboxNodeView requires a build context")
    (local fields {})
    (local theme-overrides {})
    (local row-buttons {})
    (local status-label ((Text {:text "No pending changes"}) build-ctx))
    (var active-record
         (SkyboxState.normalize-complete-state
           ((assert target.get-record "SkyboxNodeView requires target.get-record") target)
           "SkyboxNodeView initial record"))

    (fn set-status [text]
      (status-label:set-text text {:mark-measure-dirty? false}))

    (fn set-combo-value [field value]
      (field:set-value value))

    (fn set-input-value [field value]
      (field:set-text (or value "") {:mark-measure-dirty? false}))

    (set fields.enabled
         (FormComboBox build-ctx {:name "skybox-enabled"
                                  :items bool-items
                                  :value (bool-text active-record.enabled?)
                                  :placeholder "Enabled"}))
    (set fields.default-name
         (FormComboBox build-ctx {:name "skybox-default-name"
                                  :items skybox-items
                                  :value active-record.default.name
                                  :placeholder "Skybox"}))
    (set fields.default-brightness
         ((Input {:name "skybox-default-brightness"
                  :text (tostring active-record.default.brightness)
                  :placeholder "Brightness"})
          build-ctx))

    (fn apply-record-to-fields [record]
      (set active-record
           (SkyboxState.normalize-complete-state record "SkyboxNodeView refresh"))
      (set-combo-value fields.enabled (bool-text active-record.enabled?))
      (set-combo-value fields.default-name active-record.default.name)
      (set-input-value fields.default-brightness (tostring active-record.default.brightness))
      (each [theme-key row (pairs theme-overrides)]
        (local override (. active-record.by-theme theme-key))
        (set-combo-value row.name (and override override.name))
        (set-input-value row.brightness (and override (tostring override.brightness))))
      (set-status "No pending changes"))

    (local theme-section-children [])
    (each [_ entry (ipairs (theme-entries target active-record))]
      (local override (. active-record.by-theme entry.key))
      (local name-field
        (FormComboBox build-ctx {:name (.. "skybox-theme-name-" entry.key)
                                 :items skybox-items
                                 :value (and override override.name)
                                 :placeholder "Use default"}))
      (local brightness-field
        ((Input {:name (.. "skybox-theme-brightness-" entry.key)
                 :text (and override (tostring override.brightness))
                 :placeholder "Brightness"})
         build-ctx))
      (local clear-button
        ((Button {:text "Use Default"
                  :variant :secondary
                  :on-click (fn [_button _event]
                              (name-field:set-value nil)
                              (brightness-field:set-text "" {:mark-measure-dirty? false})
                              (set-status (.. "Override cleared for " entry.key)))})
         build-ctx))
      (set (. theme-overrides entry.key) {:name name-field
                                          :brightness brightness-field
                                          :unknown? entry.unknown?})
      (set (. row-buttons entry.key) clear-button)
      (table.insert theme-section-children
                    (FlexChild (theme-row entry
                                          (fn [_ctx] name-field)
                                          (fn [_ctx] brightness-field)
                                          (fn [_ctx] clear-button))
                               0)))

    (var apply-button nil)

    (fn parse-record []
      (local enabled
        (parse-bool (or (fields.enabled:get-value) "")))
      (if (= enabled nil)
          (values nil "Enabled must be true or false")
          (let [default-name (fields.default-name:get-value)
                default-brightness-text (fields.default-brightness:get-text)
                latest-record
                (SkyboxState.normalize-complete-state
                  ((assert target.get-record "SkyboxNodeView requires target.get-record") target)
                  "SkyboxNodeView latest record")]
            (if (or (= default-name nil)
                    (not (. allowed-skyboxes (tostring default-name))))
                (values nil "Default skybox must be one of the discovered choices")
                (let [(ok-default-brightness parsed-default-brightness)
                      (pcall tonumber default-brightness-text)]
                  (if (or (not ok-default-brightness)
                          (not (= (type parsed-default-brightness) :number)))
                      (values nil "Default brightness must be numeric")
                      (do
                        (local by-theme
                          (SkyboxState.clone-state latest-record.by-theme))
                        (each [theme-key row (pairs theme-overrides)]
                          (local override-name (row.name:get-value))
                          (local override-brightness-text (row.brightness:get-text))
                          (if (and (= override-name nil)
                                   (= override-brightness-text ""))
                              (set (. by-theme theme-key) nil)
                              (if (or (= override-name nil)
                                      (not (. allowed-skyboxes (tostring override-name))))
                                  (error (.. "Theme override for " theme-key
                                             " must use one of the discovered skyboxes"))
                                  (let [(ok parsed-brightness) (pcall tonumber override-brightness-text)]
                                    (if (or (not ok)
                                            (not (= (type parsed-brightness) :number)))
                                        (error (.. "Theme override brightness for "
                                                   theme-key
                                                   " must be numeric"))
                                        (set (. by-theme theme-key)
                                             {:name override-name
                                              :brightness parsed-brightness}))))))
                        (values
                          (SkyboxState.normalize-complete-state
                            {:enabled? enabled
                             :default {:name default-name
                                       :brightness parsed-default-brightness}
                             :by-theme by-theme}
                            "SkyboxNodeView apply")
                          nil))))))))

    (set apply-button
         ((Button {:text "Apply"
                   :variant :primary
                   :on-click (fn [_button _event]
                               (local (ok parsed-or-error err-message)
                                 (pcall parse-record))
                               (if (not ok)
                                   (set-status (tostring parsed-or-error))
                                   (if err-message
                                       (set-status err-message)
                                       (let [updated (target:apply-values parsed-or-error)]
                                         (if updated
                                             (do
                                               (apply-record-to-fields updated)
                                               (set-status "Applied"))
                                             (set-status "Apply failed"))))))})
          build-ctx))

    (local root
      ((Padding
         {:edge-insets [0.5 0.5]
          :child
          (Flex {:axis :y
                 :yspacing 0.5
                 :children
                 [(FlexChild (Text {:text (info-text target)}) 0)
                  (FlexChild (labeled-row "Enabled"
                                          (fn [_ctx] fields.enabled)) 0)
                  (FlexChild (labeled-row "Default skybox"
                                          (fn [_ctx] fields.default-name)) 0)
                  (FlexChild (labeled-row "Default brightness"
                                          (fn [_ctx] fields.default-brightness)) 0)
                  (FlexChild (Text {:text "Theme overrides"}) 0)
                  (FlexChild (Flex {:axis :y
                                    :yspacing 0.35
                                    :children theme-section-children})
                             0)
                  (FlexChild (fn [_ctx] status-label) 0)
                  (FlexChild (fn [_ctx] apply-button) 0)]})})
       build-ctx))

    (var changed-handler nil)
    (when (and target.changed target.changed.connect)
      (set changed-handler
           (target.changed:connect
             (fn [record]
               (apply-record-to-fields record)))))

    {:layout root.layout
     :root root
     :fields fields
     :theme-overrides theme-overrides
     :row-buttons row-buttons
     :apply-button apply-button
     :status-label status-label
     :drop (fn [self]
             (when changed-handler
               (target.changed:disconnect changed-handler true)
               (set changed-handler nil))
             (self.root:drop))})

  build)

SkyboxNodeView

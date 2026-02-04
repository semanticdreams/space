(local glm (require :glm))
(local ListView (require :list-view))
(local Button (require :button))
(local Padding (require :padding))
(local Text (require :text))
(local TextStyle (require :text-style))
(local {: Flex} (require :flex))

(local colors (require :colors))
(local logging (require :logging))
(fn ObjectBrowser [opts]
  (local options (or opts {}))

  (fn build [ctx]
    (local per-page (math.max 1 (or options.items-per-page options.num-per-page options.per-page 12)))
    (local paginate? (if (not (= options.paginate nil))
                          options.paginate
                          false))
    (local button-padding (or options.item-padding [0.5 0.4]))
    (local root-target (or options.target app.engine))
    (local root-label (or options.root-label options.title options.name "object"))
    (local browser {:context ctx
                    :root-target root-target
                    :current-target root-target
                    :path-stack []
                    :path-labels [root-label]
                    :items []
                    :list nil
                    :paginate? paginate?
                    :items-per-page per-page
                    :button-padding button-padding
                    :key-limit (math.max 8 (or options.key-limit 36))
                    :value-limit (math.max 8 (or options.value-limit 64))})

    (fn flatten-text [_self text]
      (local repr (tostring (or text "")))
      (select 1 (string.gsub repr "%s+" " ")))

    (fn trim-text [self text limit]
      (local str (self:flatten-text text))
      (local resolved-limit (math.max 2 (or limit 2)))
      (if (<= (string.len str) resolved-limit)
          str
          (.. (string.sub str 1 (- resolved-limit 1)) "…")))

    (fn safe-tostring [_self value]
      (local (ok result) (pcall (fn [] (tostring value))))
      (if ok
          result
          "<error>"))

    (fn safe-read [_self tbl key]
      (if (not (= (type tbl) :table))
          nil
          (let [(ok value) (pcall (fn [] (. tbl key)))]
            (if ok value nil))))

    (fn resolve-table-label [self tbl]
      (if (not (= (type tbl) :table))
          nil
          (let [name (self:safe-read tbl "name")
                title (self:safe-read tbl "title")
                id (self:safe-read tbl "id")
                label (or (and (= (type name) :string) name)
                          (and (= (type title) :string) title)
                          (and (= (type id) :string) id))]
            (if label
                (self:trim-text label self.value-limit)
                nil))))

    (fn describe-key [self key]
      (local key-type (type key))
      (local base
        (if (= key-type :string)
            key
            (.. "[" key-type "] " (self:safe-tostring key))))
      (self:trim-text base self.key-limit))

    (fn describe-value [self value]
      (local value-type (type value))
      (if (= value-type :string)
          (let [inner-limit (math.max 1 (- self.value-limit 2))
                inner (self:trim-text value inner-limit)]
            (.. "\"" inner "\""))
          (if (or (= value-type :number) (= value-type :boolean))
              (self:trim-text (self:safe-tostring value) self.value-limit)
              (if (= value-type :table)
                  (or (self:resolve-table-label value)
                      (self:trim-text (self:safe-tostring value) self.value-limit))
                  (if (= value-type :nil)
                      "nil"
                      (self:trim-text (self:safe-tostring value) self.value-limit))))))

    (fn normalize-entry [self key value]
      (local is-table (= (type value) :table))
      (local key-text (self:describe-key key))
      {:key key
       :value value
       :key-text key-text
       :value-text
       (if is-table
           (or (self:resolve-table-label value)
               (self:describe-value value))
           (self:describe-value value))
       :value-type (type value)
       :is-table? is-table
       :sort-key (string.lower key-text)})

    (fn collect-entries [self target dest]
      (local (ok err)
             (pcall
               (fn []
                 (each [entry-key entry-value (pairs target)]
                   (table.insert dest (self:normalize-entry entry-key entry-value))))))
      (when (not ok)
        (logging.warn (.. "[ObjectBrowser] failed to inspect value: " err))))

    (fn parent-label [self]
      (local count (length self.path-labels))
      (if (<= count 1)
          (self:trim-text (self:safe-tostring (. self.path-labels count))
                          self.value-limit)
          (let [labels []]
            (each [idx label (ipairs self.path-labels)]
              (when (< idx count)
                (table.insert labels
                              (self:trim-text (self:safe-tostring label)
                                              self.key-limit))))
            (table.concat labels " / "))))

    (fn make-parent-entry [self]
      (if (> (length self.path-stack) 0)
          {:is-up? true
           :key-text ".."
           :value-text (or (self:parent-label) "root")
           :value-type :table
           :sort-key ".."}
          nil))

    (fn build-entry-list [self]
      (local entries [])
      (local target self.current-target)
      (if (= (type target) :table)
          (self:collect-entries target entries)
          (table.insert entries
                        {:key-text "(value)"
                         :value target
                         :value-text (self:describe-value target)
                         :value-type (type target)
                         :is-table? false
                         :sort-key "(value)"}))
      (table.sort entries
                  (fn [a b]
                    (< (string.lower (or a.sort-key "")) (string.lower (or b.sort-key "")))))
      (local parent (self:make-parent-entry))
      (when parent
        (table.insert entries 1 parent))
      entries)

    (fn path-string [self]
      (local parts [])
      (each [_ label (ipairs self.path-labels)]
        (when label
          (table.insert parts
                        (self:trim-text (self:safe-tostring label) self.key-limit))))
      (if (> (length parts) 0)
          (table.concat parts " / ")
          "object"))

    (fn update-title [self]
      (when (and self.list self.list.set-title)
        (self.list:set-title (self:path-string))))

    (fn refresh-items [self]
      (local items (self:build-entry-list))
      (set self.items items)
      (when (and self.list self.list.set-items)
        (self.list:set-items items))
      (self:update-title))

    (fn dim-color [_self color factor]
      (if (not color)
          (glm.vec4 factor factor factor 1)
          (glm.vec4 (* color.x factor)
                (* color.y factor)
                (* color.z factor)
                color.w)))

    (fn resolve-entry-text-color [_self context entry]
      (local theme (and context context.theme))
      (local button-theme (and theme theme.button))
      (local variants (and button-theme button-theme.variants))
      (local button-variant
        (if entry.is-up?
            :secondary
            (if entry.is-table?
                :primary
                :tertiary)))
      (local variant-colors (and variants (. variants button-variant)))
      (local fallback-key (and button-theme button-theme.default-variant))
      (local fallback (and variants (. variants fallback-key)))
      (or (and variant-colors variant-colors.foreground)
          (and fallback fallback.foreground)
          (glm.vec4 0.9 0.9 0.9 1)))

    (fn entry-variant [_self entry]
      (if entry.is-up?
          :secondary
          (if entry.is-table?
              :primary
              :tertiary)))

    (fn build-entry-child [self entry]
      (fn [child-ctx]
        (local color (self:resolve-entry-text-color child-ctx entry))
        (local key-style (TextStyle {:color color}))
        (local value-style (TextStyle {:color (self:dim-color color 0.85)
                                       :scale 1.8}))
        (local meta-style (TextStyle {:color (self:dim-color color 0.7)
                                      :scale 1.6}))
        (local key-label (if entry.is-up? ".." entry.key-text))
        (local value-label
          (if entry.is-up?
              (.. "Back to " (or entry.value-text "parent"))
              (or entry.value-text "nil")))
        (local type-label
          (when (and (not entry.is-up?) entry.value-type)
            (.. "(" entry.value-type ")")))
        (local arrow-label (if entry.is-table? "▶" nil))
        (local children
          [{:widget (Text {:text key-label
                           :style key-style})}
           {:widget (Text {:text value-label
                           :style value-style})
            :flex 1}])
        (when type-label
          (table.insert children
                        {:widget (Text {:text type-label
                                        :style meta-style})}))
        (when arrow-label
          (table.insert children
                        {:widget (Text {:text arrow-label
                                        :style meta-style})}))
        ((Padding {:edge-insets self.button-padding
                   :child (Flex {:axis :x
                                 :spacing 0.3
                                 :yalign :center
                                 :children children})})
         child-ctx)))

    (fn build-entry [self entry child-ctx]
      ((Button {:child (self:build-entry-child entry)
                :variant :ghost
                :on-click (fn [_button _event]
                            (self:handle-entry-click entry))})
       child-ctx))

    (fn log-leaf [self entry]
      (when entry
        (local message
          (.. entry.key-text " = " (self:safe-tostring entry.value)))
        (logging.info (.. "[ObjectBrowser] " message))))

    (fn descend [self entry]
      (when (and entry entry.is-table?)
        (table.insert self.path-stack {:target self.current-target
                                       :label entry.key-text})
        (table.insert self.path-labels entry.key-text)
        (set self.current-target entry.value)
        (self:refresh-items)))

    (fn navigate-up [self]
      (local previous (table.remove self.path-stack))
      (when previous
        (table.remove self.path-labels (length self.path-labels))
        (set self.current-target previous.target)
        (self:refresh-items)))

    (fn handle-entry-click [self entry]
      (when entry
        (if entry.is-up?
            (self:navigate-up)
            (if entry.is-table?
                (self:descend entry)
                (do
                  (self:log-leaf entry)
                  (when options.on-leaf-select
                    (options.on-leaf-select self entry)))))))

    (fn drop [self]
      (when self.list
        (self.list:drop)
        (set self.list nil)))

    (set browser.flatten-text flatten-text)
    (set browser.trim-text trim-text)
    (set browser.safe-tostring safe-tostring)
    (set browser.safe-read safe-read)
    (set browser.resolve-table-label resolve-table-label)
    (set browser.describe-key describe-key)
    (set browser.describe-value describe-value)
    (set browser.normalize-entry normalize-entry)
    (set browser.collect-entries collect-entries)
    (set browser.build-entry-list build-entry-list)
    (set browser.parent-label parent-label)
    (set browser.make-parent-entry make-parent-entry)
    (set browser.path-string path-string)
    (set browser.update-title update-title)
    (set browser.refresh-items refresh-items)
    (set browser.dim-color dim-color)
    (set browser.resolve-entry-text-color resolve-entry-text-color)
    (set browser.entry-variant entry-variant)
    (set browser.build-entry-child build-entry-child)
    (set browser.build-entry build-entry)
    (set browser.log-leaf log-leaf)
    (set browser.descend descend)
    (set browser.navigate-up navigate-up)
    (set browser.handle-entry-click handle-entry-click)
    (set browser.drop drop)

    (local list-builder
      (ListView {:name (or options.name "object-browser")
                 :title root-label
                 :show-head true
                 :paginate paginate?
                 :items-per-page per-page
                 :items []
                 :builder (fn [item child-ctx]
                            (browser:build-entry item child-ctx))}))
    (local list (list-builder ctx))
    (set browser.list list)
    (set browser.layout list.layout)
    (browser:refresh-items)
    browser))

ObjectBrowser

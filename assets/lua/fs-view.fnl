(local glm (require :glm))
(local ListView (require :list-view))
(local Button (require :button))
(local Padding (require :padding))
(local Text (require :text))
(local TextStyle (require :text-style))
(local {: Flex} (require :flex))
(local fs (require :fs))
(local logging (require :logging))

(fn safe-lower [text]
  (if text
      (string.lower text)
      ""))

(fn FsView [opts]
  (assert (and fs fs.list-dir) "FsView requires the global fs module")
  (local options (or opts {}))

  (fn build [ctx]
    (local per-page (math.max 1 (or options.items-per-page options.num-per-page options.per-page 12)))
    (local include-hidden? (if (not (= options.include-hidden nil))
                                options.include-hidden
                                false))
    (local paginate? (if (not (= options.paginate nil))
                          options.paginate
                          false))
    (local button-padding (or options.item-padding [0.45 0.35]))
    (local start-path
      (or options.path
          (and fs fs.cwd (fs.cwd))
          "."))
    (local view {:context ctx
                 :include-hidden? include-hidden?
                 :items-per-page per-page
                 :paginate? paginate?
                 :button-padding button-padding
                 :items []
                 :list nil
                 :current-path start-path})

    (fn resolve-path [_self path]
      (if (and path fs fs.absolute)
          (do
            (local (ok absolute) (pcall fs.absolute path))
            (if ok absolute path))
          path))

    (fn parent-path [_self path]
      (if (not path)
          nil
          (do
            (local parent (fs.parent path))
            (if (or (= parent nil)
                    (= parent "")
                    (= parent path))
                nil
                parent))))

    (fn list-directory [self path]
      (do
        (local (ok entries) (pcall fs.list-dir path self.include-hidden?))
        (if ok
            entries
            (do
              (logging.warn (.. "FsView failed to list " path ": " entries))
              []))))

    (fn sort-entries [_self entries]
      (table.sort entries
        (fn [a b]
          (local a-dir (and a.is-dir (not a.is-up?)))
          (local b-dir (and b.is-dir (not b.is-up?)))
          (if (= a-dir b-dir)
              (< (safe-lower a.name) (safe-lower b.name))
              a-dir)))
      entries)

    (fn normalize-entry [_self entry]
      {:name entry.name
       :path entry.path
       :is-dir (and entry.is-dir true)
       :is-file (and entry.is-file true)
       :stat entry})

    (fn make-parent-entry [self path]
      (local parent (self:parent-path path))
      (if parent
          {:name ".."
           :path parent
           :is-dir true
           :is-file false
           :is-up? true
           :label ".."}
          nil))

    (fn build-entry-list [self path]
      (local raw (self:list-directory path))
      (local entries [])
      (each [_ entry (ipairs raw)]
        (table.insert entries (self:normalize-entry entry)))
      (self:sort-entries entries)
      (local parent-entry (self:make-parent-entry path))
      (when parent-entry
        (table.insert entries 1 parent-entry))
      entries)

    (fn entry-label [_self entry]
      (or entry.label
          (if entry.is-dir
              (.. entry.name "/")
              entry.name)))

    (fn entry-variant [_self entry]
      (if entry.is-dir
          :secondary
          :tertiary))

    (fn entry-icon [_self entry]
      (if entry.is-dir
          :folder
          :docs))

    (fn resolve-entry-text-color [self ctx entry]
      (local theme (and ctx ctx.theme))
      (local button-theme (and theme theme.button))
      (local variants (and button-theme button-theme.variants))
      (local variant (self:entry-variant entry))
      (local candidate (and variants (. variants variant)))
      (local fallback-key (and button-theme button-theme.default-variant))
      (local fallback (and variants (. variants fallback-key)))
      (or (and candidate candidate.foreground)
          (and fallback fallback.foreground)
          (glm.vec4 0.95 0.95 0.95 1)))

    (fn build-entry-child [self entry]
      (fn [child-ctx]
        (local color (self:resolve-entry-text-color child-ctx entry))
        (local label-style (TextStyle {:color color}))
        (local label-builder (Text {:text (self:entry-label entry)
                                    :style label-style}))
        (local icons (and child-ctx child-ctx.icons))
        (var icon-builder nil)
        (when icons
          (local icon-name (self:entry-icon entry))
          (when icon-name
            (let [(ok codepoint) (pcall (fn [] (icons:get icon-name)))]
              (when ok
                (set icon-builder
                     (Text {:codepoints [codepoint]
                            :style (TextStyle {:color color
                                               :font icons.font})}))))))
        (local content-builder
          (if icon-builder
              (Flex {:axis :x
                     :spacing 0.3
                     :yalign :center
                     :children [{:widget icon-builder}
                                {:widget label-builder :flex 1}]})
              label-builder))
        ((Padding {:edge-insets self.button-padding
                   :child content-builder})
         child-ctx)))

    (fn handle-entry-click [self entry]
      (when entry
        (if entry.is-up?
            (self:set-path entry.path)
            (if entry.is-dir
                (self:set-path entry.path)
                (do
                  (when options.on-file-activate
                    (options.on-file-activate self entry))
                  (logging.info (.. "FsView file selected: " entry.path)))))))

    (fn build-entry [self entry child-ctx]
      ((Button {:child (self:build-entry-child entry)
                :variant :ghost
                :on-click (fn [_button _event]
                            (self:handle-entry-click entry))})
       child-ctx))

    (fn update-title [self]
      (when (and self.list self.list.set-title)
        (self.list:set-title self.current-path)))

    (fn refresh-items [self]
      (local items (self:build-entry-list self.current-path))
      (set self.items items)
      (when (and self.list self.list.set-items)
        (self.list:set-items items)))

    (fn set-path [self path]
      (when path
        (set self.current-path (self:resolve-path path))
        (self:update-title)
        (self:refresh-items)
        (when options.on-path-changed
          (options.on-path-changed self {:path self.current-path}))))

    (fn drop [self]
      (when self.list
        (self.list:drop)
        (set self.list nil)))

    (set view.resolve-path resolve-path)
    (set view.parent-path parent-path)
    (set view.list-directory list-directory)
    (set view.sort-entries sort-entries)
    (set view.normalize-entry normalize-entry)
    (set view.make-parent-entry make-parent-entry)
    (set view.build-entry-list build-entry-list)
    (set view.entry-label entry-label)
    (set view.entry-variant entry-variant)
    (set view.entry-icon entry-icon)
    (set view.resolve-entry-text-color resolve-entry-text-color)
    (set view.build-entry-child build-entry-child)
    (set view.handle-entry-click handle-entry-click)
    (set view.build-entry build-entry)
    (set view.update-title update-title)
    (set view.refresh-items refresh-items)
    (set view.set-path set-path)
    (set view.drop drop)

    (local list-builder
      (ListView {:name (or options.name "fs-view")
                 :title start-path
                 :show-head true
                 :paginate false
                 :items-per-page per-page
                 :scroll-items-per-page per-page
                 :items []
                 :builder (fn [item child-ctx]
                            (view:build-entry item child-ctx))}))
    (local list (list-builder ctx))
    (set view.list list)
    (set view.layout list.layout)
    (view:set-path start-path)
    view))

FsView

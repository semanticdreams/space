(local glm (require :glm))
(local DefaultDialog (require :default-dialog))
(local {: Flex : FlexChild} (require :flex))
(local Input (require :input))
(local Button (require :button))
(local Label (require :label))
(local ListView (require :list-view))
(local Text (require :text))
(local TextStyle (require :text-style))
(local fs (require :fs))
(local Display (require :repo/display))
(local RepoBuiltins (require :llm/presets/builtins/repo))
(local repo-available! RepoBuiltins.repo-available!)

(fn ensure-workspace []
  (when (not app.repo-workspace)
    (local WorkspaceMod (require :repo/workspace))
    (local data-dir (fs.join-path app.user-data-dir "repositories"))
    (set app.repo-workspace (WorkspaceMod.Workspace {:data-dir data-dir})))
  app.repo-workspace)

(fn repo-label [repo]
  (.. repo.owner "/" repo.name))

(fn task-label [task]
  (local created (or (and task.created-at (os.date "%m-%d %H:%M" task.created-at)) ""))
  (local prompt (or task.prompt ""))
  (.. "[" task.status "] " created " | " (string.sub prompt 1 40)))

(fn WorkbenchView [opts]
  (local options (or opts {}))

  (fn build [ctx runtime-opts]
    (local incoming (or runtime-opts {}))
    (local ws (ensure-workspace))

    (local view {:ws ws
                 :repos []
                 :selected-repo-id nil
                 :tasks []
                 :clone-input nil
                 :prompt-input nil
                 :base-input nil
                 :status-text nil
                 :repo-list nil
                 :task-list nil
                 :repo-detail-label nil
                 :handlers []
                 :dropped? false})

    (fn set-status [self text]
      (when self.status-text
        (self.status-text:set-text (or text ""))))

    (fn refresh-repo-list [self]
      (when self.repo-list
        (local items [])
        (each [_ repo (ipairs self.repos)]
          (table.insert items {:id repo.id :repo repo}))
        (self.repo-list:set-items items)))

    (fn refresh-repo-detail [self]
      (when self.repo-detail-label
        (if self.selected-repo-id
            (do
              (var found nil)
              (each [_ repo (ipairs self.repos)]
                (when (= repo.id self.selected-repo-id)
                  (set found repo)))
              (if found
                  (self.repo-detail-label:set-text
                    (.. (repo-label found) "  branch: " (or found.default-branch "?")
                        "  profile: " (or found.profile "generic")))
                  (self.repo-detail-label:set-text (.. "Repo: " self.selected-repo-id))))
            (self.repo-detail-label:set-text "No repository selected"))))

    (fn refresh-task-list [self]
      (when self.task-list
        (local items [])
        (each [_ task (ipairs self.tasks)]
          (table.insert items {:id task.id :task task}))
        (self.task-list:set-items items)))

    (fn refresh-tasks [self]
      (set self.tasks [])
      (when self.selected-repo-id
        (local (ok result) (pcall ws.list-tasks ws self.selected-repo-id))
        (if ok
            (set self.tasks result)
            (set-status self (.. "Error listing tasks: " (tostring result)))))
      (refresh-task-list self))

    (fn refresh-repos [self]
      (set self.repos [])
      (set self.selected-repo-id nil)
      (set self.tasks [])
      (local (ok result) (pcall ws.list-repos ws))
      (if ok
          (each [_ repo (ipairs result)]
            (local (ok-url _url) (pcall Display.safe-display-url repo))
            (if ok-url
                (table.insert self.repos repo)
                (set-status self (.. "Skipping corrupt registry entry: " (tostring repo.id)))))
          (set-status self (.. "Error listing repos: " (tostring result))))
      (refresh-repo-list self)
      (refresh-repo-detail self)
      (refresh-task-list self))

    (fn clone-deferred [self url]
      (if self.dropped?
          nil
          (do
            (local (ok result) (pcall ws.clone-repo ws url))
            (if (and (not self.dropped?) ok)
                (do
                  (repo-available! app)
                  (set-status self (.. "Cloned: " (repo-label result)))
                  (self.clone-input:set-text "")
                  (refresh-repos self))
                (when (not self.dropped?)
                  (set-status self (.. "Clone failed: " (tostring result))))))))

    (fn create-task-deferred [self repo-id prompt effective-base]
      (if self.dropped?
          nil
          (do
            (local (ok result) (pcall ws.create-task ws repo-id prompt effective-base))
            (if (and (not self.dropped?) ok)
                (do
                  (set-status self (.. "Task created: " result.id))
                  (self.prompt-input:set-text "")
                  (when (= self.selected-repo-id repo-id)
                    (refresh-tasks self)))
                (when (not self.dropped?)
                  (set-status self (.. "Create task failed: " (tostring result))))))))

    (fn handle-clone [self]
      (when self.clone-input
        (local url (self.clone-input:get-text))
        (if (not (and url (string.match url "%S")))
            (set-status self "Enter a remote URL to clone")
            (do
              (set-status self (.. "Cloning " url "..."))
              (app.next-frame (fn [] (clone-deferred self url)))))))

    (fn handle-select-repo [self repo-id]
      (set self.selected-repo-id repo-id)
      (refresh-repo-detail self)
      (refresh-tasks self))

    (fn handle-create-task [self]
      (if (not self.selected-repo-id)
          (set-status self "Select a repository first")
          self.prompt-input
           (do
            (local repo-id self.selected-repo-id)
            (local prompt (self.prompt-input:get-text))
            (if (not (and prompt (string.match prompt "%S")))
                (set-status self "Enter a task prompt")
                (do
                  (local base-text (self.base-input:get-text))
                  (local effective-base (if (and base-text (string.match base-text "%S"))
                                            base-text
                                            nil))
                  (set-status self "Creating task...")
                  (app.next-frame (fn []
                                    (create-task-deferred self repo-id prompt effective-base))))))))

    (set view.handle-clone handle-clone)
    (set view.handle-create-task handle-create-task)

    ;; --- Widget Build ---

    (local clone-input
      ((Input {:text ""
               :placeholder "https://github.com/owner/repo.git"
               :name "repo-clone-url"
               :min-columns 24
               :max-columns 60})
       ctx))

    (local clone-button
      ((Button {:text "Clone"
                :variant :primary
                :on-click (fn [_btn _evt]
                            (handle-clone view))})
       ctx))

    (local clone-row
      ((Flex {:axis 1
              :xspacing 0.4
              :yalign :stretch
              :children [(FlexChild (fn [_c] clone-input) 1)
                         (FlexChild (fn [_c] clone-button) 0)]})
       ctx))

    (local status-text-widget
      ((Text {:text ""
              :style (TextStyle {:color (or (and ctx ctx.theme ctx.theme.text ctx.theme.text.dim-foreground)
                                            (glm.vec4 0.55 0.58 0.64 1))})})
       ctx))
    (set view.status-text status-text-widget)

    (local repo-list-widget
      ((ListView {:name "repo-list"
                  :title "Repositories"
                  :show-head true
                  :items []
                  :scroll true
                  :scroll-items-per-page 6
                  :scrollbar-policy :as-needed
                  :builder (fn [item child-ctx]
                             ((Button {:text (repo-label item.repo)
                                       :variant :ghost
                                       :xalign :start
                                       :on-click (fn [_btn _evt]
                                                   (handle-select-repo view item.id))})
                              child-ctx))})
       ctx))
    (set view.repo-list repo-list-widget)

    (local repo-detail-label
      ((Text {:text "No repository selected"
              :style (TextStyle {:color (or (and ctx ctx.theme ctx.theme.text ctx.theme.text.dim-foreground)
                                            (glm.vec4 0.55 0.58 0.64 1))})})
       ctx))
    (set view.repo-detail-label repo-detail-label)

    (local task-list-widget
      ((ListView {:name "task-list"
                  :title "Tasks"
                  :show-head true
                  :items []
                  :scroll true
                  :scroll-items-per-page 4
                  :scrollbar-policy :as-needed
                  :builder (fn [item child-ctx]
                             ((Label {:text (task-label item.task)})
                              child-ctx))})
       ctx))
    (set view.task-list task-list-widget)

    (local prompt-input
      ((Input {:text ""
               :placeholder "Describe the task..."
               :name "repo-task-prompt"
               :min-columns 20
               :max-columns 60})
       ctx))

    (local base-input
      ((Input {:text ""
               :placeholder "Base branch (default)"
               :name "repo-task-base"
               :min-columns 12
               :max-columns 30})
       ctx))

    (local create-button
      ((Button {:text "Create Task"
                :variant :primary
                :on-click (fn [_btn _evt]
                            (handle-create-task view))})
       ctx))

    (local task-create-row
      ((Flex {:axis 1
              :xspacing 0.4
              :yalign :stretch
              :children [(FlexChild (fn [_c] prompt-input) 1)
                         (FlexChild (fn [_c] base-input) 0)
                         (FlexChild (fn [_c] create-button) 0)]})
       ctx))

    (set view.clone-input clone-input)
    (set view.prompt-input prompt-input)
    (set view.base-input base-input)

    (fn build-content [child-ctx]
      ((Flex {:axis 2
              :yspacing 0.4
              :xalign :stretch
              :children [(FlexChild (fn [_c] clone-row) 0)
                         (FlexChild (fn [_c] status-text-widget) 0)
                         (FlexChild (fn [_c] repo-list-widget) 0)
                         (FlexChild (fn [_c] repo-detail-label) 0)
                         (FlexChild (fn [_c] task-list-widget) 1)
                         (FlexChild (fn [_c] task-create-row) 0)]})
       child-ctx))

    (local dialog
      ((DefaultDialog {:title "Repository Workbench"
                       :name "repo-workbench-dialog"
                       :on-close incoming.on-close
                       :child build-content})
       ctx))

    (set dialog.__view view)

    (local base-drop dialog.drop)
    (set dialog.drop
         (fn [self]
           (set view.dropped? true)
           (each [_ record (ipairs view.handlers)]
             (when (and record record.signal record.handler)
               (record.signal:disconnect record.handler true)))
           (when base-drop
             (base-drop self))))

    (refresh-repos view)
    dialog)

  build)

(local exports {:WorkbenchView WorkbenchView})

(setmetatable exports {:__call (fn [_ ...]
                                 (WorkbenchView ...))})

exports

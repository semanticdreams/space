(local glm (require :glm))
(local DefaultDialog (require :default-dialog))
(local ListView (require :list-view))
(local Input (require :input))
(local Button (require :button))
(local Padding (require :padding))
(local Sized (require :sized))
(local {: Flex : FlexChild} (require :flex))
(local {: Layout} (require :layout))
(local LlmStore (require :llm/store))

(fn copy-table [source]
  (local clone {})
  (when source
    (each [k v (pairs source)]
      (set (. clone k) v)))
  clone)

(fn merge-options [base incoming]
  (local merged (copy-table base))
  (each [k v (pairs (or incoming {}))]
    (set (. merged k) v))
  merged)

(fn entry-label [record]
  (assert record "entry-label requires a record")
  (if (= record.type "message")
      (do
        (local role (string.upper (or record.role "user")))
        (local body (or record.content ""))
        (.. role ": " body))
      (if (= record.type "tool-call")
          (do
            (local name (or record.name "tool"))
            (.. "Tool call: " name "\n" (or record.arguments "")))
          (if (= record.type "tool-result")
              (do
                (local name (or record.name "tool"))
                (.. "Tool result: " name "\n" (or record.output "")))
              (tostring (or record.type "item"))))))

(fn count-lines [text]
  (if (not text)
      1
      (do
        (var line-count 1)
        (each [_ _ (string.gmatch text "\n")]
          (set line-count (+ line-count 1)))
        line-count)))

(fn normalize-parent-key [record root-key]
  (assert record "normalize-parent-key requires a record")
  (assert root-key "normalize-parent-key requires a root key")
  (if record.parent_id
      (tostring record.parent_id)
      root-key))

(fn ensure-list [tbl key]
  (local existing (. tbl key))
  (if existing
      existing
      (do
        (local created [])
        (set (. tbl key) created)
        created)))

(fn sort-by-order! [items]
  (table.sort items (fn [a b]
                      (< (or a.order 0)
                         (or b.order 0))))
  items)

(fn build-index [items root-key]
  (local children-by-parent {})
  (local by-id {})
  (each [_ record (ipairs (or items []))]
    (set (. by-id (tostring record.id)) record)
    (local parent-key (normalize-parent-key record root-key))
    (table.insert (ensure-list children-by-parent parent-key) record))
  (each [_ children (pairs children-by-parent)]
    (sort-by-order! children))
  (values children-by-parent by-id))

(fn find-child-index [siblings id]
  (local key (tostring id))
  (var idx 1)
  (var found nil)
  (while (and (<= idx (length siblings)) (not found))
    (local entry (. siblings idx))
    (when (and entry (= (tostring entry.id) key))
      (set found idx))
    (set idx (+ idx 1)))
  found)

(fn resolve-selected-child [selection parent-key siblings]
  (assert selection "resolve-selected-child requires a selection table")
  (assert parent-key "resolve-selected-child requires a parent key")
  (assert siblings "resolve-selected-child requires siblings")
  (local preferred (. selection parent-key))
  (local idx
    (if preferred
        (find-child-index siblings preferred)
        nil))
  (if idx
      (values (. siblings idx) idx)
      (do
        (local first (. siblings 1))
        (when first
          (set (. selection parent-key) (tostring first.id)))
        (values first 1))))

(fn build-nav-spacer [opts]
  (local options (or opts {}))
  (local width (math.max 0 (or options.width 1.2)))
  (local height (math.max 0 (or options.height 1.6)))
  (fn build [_ctx]
    (local widget {})
    (local layout
      (Layout {:name "llm-conversation-nav-spacer"
               :measurer (fn [self]
                           (set self.measure (glm.vec3 width height 0)))
               :layouter (fn [_self] nil)}))
    (set widget.layout layout)
    (set widget.drop (fn [_self]
                       (when layout
                         (layout:drop))))
    widget))

(fn build-path [view items root-key]
  (assert view "build-path requires a view")
  (assert root-key "build-path requires a root key")
  (local selection (or view.branch-selection {}))
  (set view.branch-selection selection)
  (local (children-by-parent by-id) (build-index items root-key))
  (set view.children-by-parent children-by-parent)
  (set view.items-by-id by-id)
  (var parent-key root-key)
  (var entries [])
  (local visited {})
  (var done? false)
  (while (not done?)
    (local siblings (. children-by-parent parent-key))
    (when (not (and siblings (> (length siblings) 0)))
      (set done? true))
    (when (and (not done?) siblings)
      (local (record idx) (resolve-selected-child selection parent-key siblings))
      (when (not record)
        (set done? true))
      (when (not done?)
        (local id-key (tostring record.id))
        (when (. visited id-key)
          (error "Detected a cycle in conversation item tree"))
        (set (. visited id-key) true)

        (local label (entry-label record))
        (local line-count (count-lines label))
        (local sibling-count (length siblings))
        (table.insert entries
                      {:id id-key
                       :record record
                       :parent-key parent-key
                       :sibling-index idx
                       :sibling-count sibling-count
                       :label label
                       :line-count line-count})
        (set parent-key id-key))))
  entries)

(fn build-message-row [view entry child-ctx]
  (assert view "build-message-row requires a view")
  (assert entry "build-message-row requires an entry")
  (local label (or entry.label ""))
  (local nav-width 1.2)
  (local nav-height 1.6)
  (var left-button nil)
  (var right-button nil)

  (fn shift-sibling [direction]
    (assert direction "shift-sibling requires a direction")
    (local parent-key entry.parent-key)
    (local siblings (and view.children-by-parent (. view.children-by-parent parent-key)))
    (when (and siblings (> (length siblings) 1))
      (local current-index (or entry.sibling-index 1))
      (local next-index
        (if (= direction :left)
            (math.max 1 (- current-index 1))
            (math.min (length siblings) (+ current-index 1))))
      (when (not (= next-index current-index))
        (local next-record (. siblings next-index))
        (when next-record
          (set (. view.branch-selection parent-key) (tostring next-record.id))
          (view:refresh)))))

  (local left-widget
    (if (and (> (or entry.sibling-count 0) 1)
             (> (or entry.sibling-index 1) 1))
        (do
          (set left-button
               ((Button {:text "<"
                         :variant :ghost
                         :padding [0.25 0.35]
                         :on-click (fn [_button _event]
                                     (shift-sibling :left))})
                child-ctx))
          left-button)
        ((build-nav-spacer {:width nav-width :height nav-height}) child-ctx)))

  (local right-widget
    (if (and (> (or entry.sibling-count 0) 1)
             (< (or entry.sibling-index 1) (or entry.sibling-count 1)))
        (do
          (set right-button
               ((Button {:text ">"
                         :variant :ghost
                         :padding [0.25 0.35]
                         :on-click (fn [_button _event]
                                     (shift-sibling :right))})
                child-ctx))
          right-button)
        ((build-nav-spacer {:width nav-width :height nav-height}) child-ctx)))

  (local text-input
    ((Input {:text ""
             :multiline? true
             :min-lines 3
             :max-lines 3
             :min-columns 12
             :max-columns 90
             :name "llm-conversation-message-entry"})
     child-ctx))
  (when (and text-input text-input.set-text)
    (text-input:set-text label {:reset-cursor? false}))

  (local content
    ((Padding {:edge-insets [0.35 0.35]
               :child (fn [_] text-input)})
     child-ctx))

  (local row
    ((Flex {:axis 1
            :xalign :stretch
            :yalign :center
            :xspacing 0.4
            :children [(FlexChild (fn [_] left-widget) 0)
                       (FlexChild (fn [_] content) 1)
                       (FlexChild (fn [_] right-widget) 0)]})
     child-ctx))
  (set row.left-button left-button)
  (set row.right-button right-button)
  (set row.message-input text-input)
  row)

(fn LlmConversationMessagesView [opts]
  (local base-options (or opts {}))

  (fn build [ctx runtime-opts]
    (local options (merge-options base-options runtime-opts))
    (local node options.node)
    (local store (or options.store (and node node.store) (LlmStore.get-default)))
    (local conversation-id (or options.conversation-id (and node node.llm-id)))
    (assert store "LlmConversationMessagesView requires a store")
    (assert conversation-id "LlmConversationMessagesView requires a conversation-id")
    (local view {:store store
                 :conversation-id conversation-id
                 :node node
                 :handlers []
                 :branch-selection {}
                 :children-by-parent {}
                 :items-by-id {}
                 :conversation-item-ids {}
                 :list nil})

    (fn track-conversation-items [self items]
      (local ids {})
      (each [_ record (ipairs (or items []))]
        (when record
          (set (. ids (tostring record.id)) true)))
      (set self.conversation-item-ids ids))

    (fn refresh [self]
      (local items (store:list-conversation-items conversation-id))
      (track-conversation-items self items)
      (local root-key (tostring conversation-id))
      (local entries (build-path self items root-key))
      (when (and self.list self.list.set-items)
        (self.list:set-items entries)))

    (set view.refresh refresh)

    (local list
      ((ListView {:name "llm-conversation-messages-list"
                  :items []
                  :show-head false
                  :item-spacing 0.45
                  :builder (fn [entry child-ctx]
                             (build-message-row view entry child-ctx))})
       ctx))
    (set view.list list)

    (local content
      ((Sized {:size (or options.size (glm.vec3 80 55 0))
               :child (fn [_] list)})
       ctx))

    (local dialog
      ((DefaultDialog {:title (or options.title "Conversation Messages")
                       :name (or options.name "llm-conversation-messages-view")
                       :resizeable true
                       :on-close options.on-close
                       :child (fn [_] content)})
       ctx))
    (set dialog.__messages-view view)

    (local items-handler
      (store.conversation-items-changed:connect
        (fn [payload]
          (when (= (tostring (or (and payload payload.conversation_id) ""))
                   (tostring conversation-id))
            (view:refresh)))))
    (table.insert view.handlers {:signal store.conversation-items-changed
                                 :handler items-handler})

    (local message-handler
      (store.message-changed:connect
        (fn [record]
          (local id (and record record.id))
          (when (and id (. view.conversation-item-ids (tostring id)))
            (view:refresh)))))
    (table.insert view.handlers {:signal store.message-changed
                                 :handler message-handler})

    (view:refresh)

    (local base-drop dialog.drop)
    (set dialog.drop
         (fn [self]
           (each [_ record (ipairs view.handlers)]
             (when (and record record.signal record.handler)
               (record.signal:disconnect record.handler true)))
           (when base-drop
             (base-drop self))))

    dialog)

  build)

(local exports {:LlmConversationMessagesView LlmConversationMessagesView})

(setmetatable exports {:__call (fn [_ ...]
                                 (LlmConversationMessagesView ...))})

exports

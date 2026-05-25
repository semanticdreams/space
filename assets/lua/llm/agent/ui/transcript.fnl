;; Transcript — renders the session item stream inside a ScrollView.

(local ScrollView (require :scroll-view))
(local {: Flex : FlexChild} (require :flex))
(local item-row (require :llm/agent/ui/item-row))
(local build-item-rows item-row.build-item-rows)
(local Text (require :text))
(local TextStyle (require :text-style))
(local Padding (require :padding))
(local {: Layout} (require :layout))
(local glm (require :glm))

(fn AgentTranscript [controller]
  (fn build [ctx]
    (var item-rows [])
    (var inner-flex nil)
    (var last-item-count 0)
    (var current-items-signature "")

    (local dim-foreground
      (or (and ctx ctx.theme ctx.theme.text ctx.theme.text.dim-foreground)
          (glm.vec4 0.45 0.48 0.55 1)))

    (local empty-text
      ((Text {:text "No messages yet."
              :style (TextStyle {:color dim-foreground
                                 :scale 1.3})})
       ctx))
    (var empty-padded
      ((Padding {:edge-insets [1.0 0.5]
                 :child (fn [_ctx] empty-text)})
       ctx))

    (var active-child empty-padded)

    (fn content-measurer [self]
      (active-child.layout:measurer)
      (set self.measure active-child.layout.measure))

    (fn content-constrained-measurer [self constraints]
      (active-child.layout:measure-constrained constraints)
      (set self.measure active-child.layout.measure))

    (fn content-layouter [self]
      (set active-child.layout.size self.size)
      (set active-child.layout.position self.position)
      (set active-child.layout.rotation self.rotation)
      (set active-child.layout.depth-offset-index self.depth-offset-index)
      (set active-child.layout.clip-region self.clip-region)
      (active-child.layout:layouter))

    (local content-layout
      (Layout {:name "agent-transcript-content"
               :children [empty-padded.layout]
               :measurer content-measurer
               :constrained-measurer content-constrained-measurer
               :layouter content-layouter}))

    (local content-root
      {:layout content-layout
       :drop (fn [self]
               (self.layout:drop)
               (when inner-flex
                 (inner-flex:drop)
                 (set inner-flex nil))
               (when empty-padded
                 (empty-padded:drop)
                 (set empty-padded nil)))})

    (local scroll-view
      ((ScrollView {:child (fn [_ctx] content-root)
                    :scrollbar-policy :as-needed
                    :scrollbar-width 0.5
                    :name "agent-transcript"})
       ctx))

    (fn set-active-child [child]
      (set active-child child)
      (content-layout:set-children [child.layout])
      (content-layout:mark-measure-dirty)
      (content-layout:mark-layout-dirty))

    (fn drop-and-rebuild-empty []
      (when (not empty-padded)
        (set empty-padded
             ((Padding {:edge-insets [1.0 0.5]
                        :child (fn [_ctx]
                                 ((Text {:text "No messages yet."
                                         :style (TextStyle {:color dim-foreground
                                                            :scale 1.3})})
                                  _ctx))})
              ctx))))

    (fn items-signature [items]
      (local parts [])
      (each [_ item (ipairs items)]
        (table.insert parts (.. (tostring (or item.type :unknown))
                                ":"
                                (tostring (or item.id :missing-id)))))
      (table.concat parts "|"))

    (fn update-existing-rows [items]
      (local visible-items (item-row.pair-tool-items items))
      (var updated? true)
      (if (not (= (length visible-items) (length item-rows)))
          (set updated? false)
          (each [index row (ipairs item-rows)]
            (local item (. visible-items index))
            (if (and item row.update (= row.item-id item.id))
                (row:update item items)
                (set updated? false))))
      updated?)

    (fn rebuild-inner [items item-count should-scroll-to-end next-signature]
      (when inner-flex
        (inner-flex:drop)
        (set inner-flex nil))
      (if (> item-count 0)
          (do
            (when (= active-child empty-padded)
              (empty-padded:drop)
              (set empty-padded nil))
            (set item-rows (build-item-rows controller items ctx))
            (set inner-flex
                 ((Flex {:axis 2
                         :xalign :stretch
                         :yspacing 0.1
                         :children (icollect [_ row (ipairs item-rows)]
                                                 (FlexChild (fn [_ctx] row.widget) 0))})
                  ctx))
            (set-active-child inner-flex))
          (do
            (set item-rows [])
            (drop-and-rebuild-empty)
            (set-active-child empty-padded)))
      (set current-items-signature next-signature)
      (set last-item-count item-count)
      (when (and inner-flex should-scroll-to-end)
        (scroll-view:reset-scroll-position))
      (when scroll-view.layout
        (scroll-view.layout:mark-measure-dirty)))

    (fn build-inner []
      (local items controller.state.items)
      (local item-count (length items))
      (local next-signature (items-signature items))
      (local should-scroll-to-end (> item-count last-item-count))
      (if (and inner-flex (> item-count 0) (= next-signature current-items-signature)
               (update-existing-rows items))
          (do
            (set last-item-count item-count)
            (content-layout:mark-measure-dirty)
            (when scroll-view.layout
              (scroll-view.layout:mark-measure-dirty)))
          (rebuild-inner items item-count should-scroll-to-end next-signature)))

    (build-inner)

    (fn refresh [self]
      (build-inner))

    (fn drop [self]
      (scroll-view:drop))

    {:layout scroll-view.layout
     :drop drop
     :refresh refresh
     :scroll-view scroll-view}))

{:AgentTranscript AgentTranscript}

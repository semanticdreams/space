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

    (local empty-text
      ((Text {:text "No messages yet."
              :style (TextStyle {:color (glm.vec4 0.45 0.48 0.55 1)
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
                                         :style (TextStyle {:color (glm.vec4 0.45 0.48 0.55 1)
                                                            :scale 1.3})})
                                  _ctx))})
              ctx))))

    (fn build-inner []
      (when inner-flex
        (inner-flex:drop)
        (set inner-flex nil))
      (local items controller.state.items)
      (if (> (length items) 0)
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
      (when inner-flex
        (scroll-view:reset-scroll-position))
      (when scroll-view.layout
        (scroll-view.layout:mark-measure-dirty)))

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

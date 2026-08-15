(local {: Flex : FlexChild} (require :flex))
(local Text (require :text))

(fn resolve-target [node options]
  (if node node (assert options.node "AgentSessionNodePreview requires node")))

(fn resolve-build-ctx [ctx]
  (if ctx
      ctx
      (error "AgentSessionNodePreview requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn current-session [target]
  (when (and target target.current-session)
    (target:current-session))
  (assert target.agent-session "AgentSessionNodePreview requires projected agent session"))

(fn item-count [session]
  (length (if (and session session.items) session.items [])))

(fn session-summary [target]
  (local session (current-session target))
  (local session-id (if session.id session.id target.workflow-run-id))
  (local status (if session.status session.status :pending))
  (local agent-id (if session.agent-id session.agent-id "unknown"))
  (.. "Session: " (tostring session-id)
      "\nStatus: " (tostring status)
      "\nAgent: " (tostring agent-id)
      "\nItems: " (item-count session)))

(fn build-content [target build-ctx]
  (local view {})
  (local label (if (and target target.label) target.label target.key target.key "Agent session"))
  (local title ((Text {:text (tostring label)}) build-ctx))
  (local summary-text ((Text {:text (session-summary target)}) build-ctx))
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
            :children [(FlexChild (existing-widget title) 0)
                       (FlexChild (existing-widget summary-text) 0)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.summary-text summary-text)
  (set view.flex flex)
  (set view.drop
       (fn [_self]
         (title:drop)
         (summary-text:drop)
         (flex:drop)))
  view)

(fn AgentSessionNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

AgentSessionNodePreview

;; Item row dispatcher — creates the right row builder for each session item type.

(local glm (require :glm))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Padding (require :padding))
(local {: Flex : FlexChild} (require :flex))
(local Stack (require :stack))
(local Rectangle (require :rectangle))
(local DisclosureRow (require :disclosure-row))
(local StatusBadge (require :status-badge))
(local Button (require :button))
(local json (require :json))
(local gl (require :gl))

(fn resolve-transcript-role [ctx role]
  (local theme (and ctx ctx.theme))
  (local transcript (and theme theme.transcript))
  (and transcript (. transcript role)))

(fn dim-foreground [ctx]
  (or (and ctx ctx.theme ctx.theme.text ctx.theme.text.dim-foreground)
      (glm.vec4 0.55 0.58 0.64 1)))

(fn code-font [ctx]
  (when (= (type ctx.theme) :table)
    (local theme ctx.theme)
    (or (and theme.code-font)
        theme.font)))

(fn code-style [ctx color]
  (local tool-role (resolve-transcript-role ctx :tool))
  (TextStyle {:font (code-font ctx)
              :color (or color (and tool-role tool-role.foreground) (glm.vec4 0.82 0.85 0.9 1))
              :scale 1.1}))

(fn make-message-row [item controller ctx]
  (local is-user? (= item.role :user))
  (local role (resolve-transcript-role ctx (if is-user? :user :assistant)))
  (local bg-color (or (and role role.background) (glm.vec4 0.12 0.13 0.17 0.95)))
  (local text-color (or (and role role.foreground) (glm.vec4 0.88 0.9 0.95 1)))
  (local label (if is-user? "user" "assistant"))

  (local bg-rect ((Rectangle {:color bg-color}) ctx))
  (local content-text
    ((Text {:text (or item.content "")
            :style (TextStyle {:color text-color :scale 1.3})})
     ctx))
  (local content-padded
    ((Padding {:edge-insets [0.4 0.45]
               :child (fn [_ctx] content-text)})
     ctx))

  (local copy-btn
    ((Button {:icon "content_copy"
              :variant :ghost
              :icon-style {:scale 1.0}
              :padding [0.2 0.2]
              :on-click (fn [_btn _evt]
                          (gl.clipboard-set (or item.content "")))})
     ctx))

  (local label-text
    ((Text {:text label
             :style (TextStyle {:color (dim-foreground ctx)
                                :scale 1.1})})
     ctx))

  (local header-row
    ((Flex {:axis 1
            :xspacing 0.3
            :yalign :center
            :children [(FlexChild (fn [_ctx] label-text) 1)
                       (FlexChild (fn [_ctx] copy-btn))]})
     ctx))

  (local header-padded
    ((Padding {:edge-insets [0.25 0.45 0 0.45]
               :child (fn [_ctx] header-row)})
     ctx))

  (local stack
    ((Stack {:children [(fn [_ctx] bg-rect)
                          (fn [_ctx] ((Flex {:axis 2
                                             :xalign :stretch
                                             :yspacing 0
                                             :children [(FlexChild (fn [_ctx] header-padded))
                                                        (FlexChild (fn [_ctx] content-padded) 1)]})
                                      _ctx))]})
     ctx))

  {:widget stack
   :type :message})

(fn find-matching-result [items call-id]
  (var result nil)
  (each [_ item (ipairs items)]
    (when (and (= item.type :tool-result) (= item.call-id call-id))
      (set result item)))
  result)

(fn make-tool-row [item items controller ctx]
  (local call-id item.call-id)
  (local result (find-matching-result items call-id))
  (local is-error? (and result result.is-error))
  (local is-running? (and (not result) controller.state.active-turn))
  (local status-tone (if is-error? :danger
                         is-running? :info
                         :success))
  (local status-text (if is-error? "failed"
                         is-running? "running"
                         "ok"))

  (local expanded? (controller:is-expanded? item.id))

  (fn summary-builder [summary-ctx]
    (local tool-name
      ((Text {:text (.. "▸ " (or item.name "tool"))
              :style (code-style summary-ctx)})
       summary-ctx))
    (local status
      ((StatusBadge {:text status-text :tone status-tone :scale 1.0 :padding [0.15 0.1]})
       summary-ctx))
    ((Flex {:axis 1
            :xspacing 0.3
            :yalign :center
            :children [(FlexChild (fn [_ctx] tool-name))
                       (FlexChild (fn [_ctx] status))]})
     summary-ctx))

  (fn details-builder [details-ctx]
    (local parts [])
    (when item.arguments
      (table.insert parts
        (.. "args: " (if (= (type item.arguments) :string)
                          item.arguments
                          (json.dumps item.arguments)))))
    (when (and result result.output)
      (table.insert parts
        (.. "output: " result.output)))
    (local details-text
      (if (> (length parts) 0)
          (table.concat parts "\n")
          "No details available"))
    ((Padding {:edge-insets [0.3 0.8]
               :child (fn [_ctx]
                         ((Text {:text details-text
                                 :style (code-style details-ctx)})
                          _ctx))})
     details-ctx))

  (local disclosure
    ((DisclosureRow {:summary summary-builder
                     :details details-builder
                     :expanded? expanded?
                     :on-toggle (fn [_should-expand]
                                  (controller:toggle-expanded item.id))})
     ctx))

  (local tool-role (resolve-transcript-role ctx :tool))
  (local bg-rect
    ((Rectangle {:color (or (and tool-role tool-role.background) (glm.vec4 0.1 0.14 0.18 0.95))}) ctx))
  (local padded
    ((Padding {:edge-insets [0.25 0.25]
               :child (fn [_ctx] disclosure)})
     ctx))
  (local stack
    ((Stack {:children [(fn [_ctx] bg-rect) (fn [_ctx] padded)]})
     ctx))

  {:widget stack
   :type :tool-call})

(fn make-tool-result-row [item _controller ctx]
  (local is-error? item.is-error)
  (local role (resolve-transcript-role ctx (if is-error? :error :tool)))
  (local bg-color (or (and role role.background) (glm.vec4 0.1 0.14 0.18 0.95)))
  (local text-color (or (and role role.foreground) (glm.vec4 0.82 0.85 0.9 1)))
  (local status-text (if is-error? "tool error" "tool result"))

  (local bg-rect ((Rectangle {:color bg-color}) ctx))
  (local status
    ((StatusBadge {:text status-text
                   :tone (if is-error? :danger :neutral)
                   :scale 1.0
                   :padding [0.15 0.1]})
     ctx))
  (local name-text
    ((Text {:text (.. (or item.name "tool") ": " (or item.output ""))
            :style (code-style ctx text-color)})
     ctx))
  (local padded
    ((Padding {:edge-insets [0.3 0.45]
               :child (fn [_ctx]
                        ((Flex {:axis 2
                                :yspacing 0.2
                                :children [(FlexChild (fn [_ctx] status))
                                           (FlexChild (fn [_ctx] name-text))]})
                         _ctx))})
     ctx))
  (local stack
    ((Stack {:children [(fn [_ctx] bg-rect) (fn [_ctx] padded)]})
     ctx))

  {:widget stack
   :type :tool-result})

(fn make-error-row [item _controller ctx]
  (local role (resolve-transcript-role ctx :error))
  (local bg-color (or (and role role.background) (glm.vec4 0.28 0.1 0.12 0.95)))
  (local text-color (or (and role role.foreground) (glm.vec4 0.98 0.75 0.72 1)))
  (local bg-rect ((Rectangle {:color bg-color}) ctx))
  (local error-text
    ((Text {:text (.. "error: " (or item.error "unknown error"))
            :style (TextStyle {:color text-color :scale 1.3})})
     ctx))
  (local padded
    ((Padding {:edge-insets [0.4 0.45]
               :child (fn [_ctx] error-text)})
     ctx))
  (local stack
    ((Stack {:children [(fn [_ctx] bg-rect) (fn [_ctx] padded)]})
     ctx))

  {:widget stack
   :type :error})

(fn make-event-row [item _controller ctx]
  (local role (resolve-transcript-role ctx :event))
  (local text-color (or (and role role.foreground) (glm.vec4 0.55 0.58 0.64 1)))
  (local text
    ((Text {:text (or item.event "")
            :style (TextStyle {:color text-color :scale 1.1})})
     ctx))
  (local padded
    ((Padding {:edge-insets [0.2 0.45]
               :child (fn [_ctx] text)})
     ctx))

  {:widget padded
   :type :event})

(fn pair-tool-items [items]
  (local has-call {})
  (each [_ item (ipairs items)]
    (when (= item.type :tool-call)
      (tset has-call item.call-id true)))
  (local result [])
  (each [_ item (ipairs items)]
    (if (= item.type :tool-result)
        (when (not (. has-call item.call-id))
          (table.insert result item))
        (table.insert result item)))
  result)

(fn build-item-rows [controller items ctx]
  (local visible-items (pair-tool-items items))
  (local rows [])
  (each [_ item (ipairs visible-items)]
    (var row nil)
    (if (= item.type :message)
        (set row (make-message-row item controller ctx))
        (= item.type :tool-call)
        (set row (make-tool-row item items controller ctx))
        (= item.type :tool-result)
        (set row (make-tool-result-row item controller ctx))
        (= item.type :error)
        (set row (make-error-row item controller ctx))
        (= item.type :event)
        (set row (make-event-row item controller ctx)))
    (when row
      (table.insert rows row)))
  rows)

{:build-item-rows build-item-rows}

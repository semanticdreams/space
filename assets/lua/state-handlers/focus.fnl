(local Runtime (require :state-runtime))

(local InputKeyDownDispatch
  {:key-down (fn [ctx payload]
               (if (Runtime.dispatch-input :on-key-down payload)
                   (do
                     ((. ctx :mark-command-executed!))
                     true)
                   false))})

(local InputKeyUpDispatch
  {:key-up (fn [_ctx payload]
             (Runtime.dispatch-input :on-key-up payload))})

(local FocusTabKeyDown
  {:key-down (fn [ctx payload]
               (if (Runtime.handle-focus-tab ctx payload)
                   (do
                     ((. ctx :mark-command-executed!))
                     true)
                   false))})

(local FocusDirectionKeyDown
  {:key-down (fn [ctx payload]
               (if (Runtime.handle-focus-direction ctx payload)
                   (do
                     ((. ctx :mark-command-executed!))
                     true)
                   false))})

(local ActiveInputKeyBlock
  {:key-down (fn [_ctx _payload]
               (if (Runtime.active-input) true false))
   :key-up (fn [_ctx _payload]
             (if (Runtime.active-input) true false))})

{:InputKeyDownDispatch InputKeyDownDispatch
 :InputKeyUpDispatch InputKeyUpDispatch
 :FocusTabKeyDown FocusTabKeyDown
 :FocusDirectionKeyDown FocusDirectionKeyDown
 :ActiveInputKeyBlock ActiveInputKeyBlock}

(local Runtime (require :state-runtime))

(local InputKeyDownDispatch
  {:key-down (fn [_ctx payload]
               (Runtime.dispatch-input :on-key-down payload))})

(local InputKeyUpDispatch
  {:key-up (fn [_ctx payload]
             (Runtime.dispatch-input :on-key-up payload))})

(local FocusTabKeyDown
  {:key-down (fn [_ctx payload]
               (Runtime.handle-focus-tab payload))})

(local FocusDirectionKeyDown
  {:key-down (fn [_ctx payload]
               (Runtime.handle-focus-direction payload))})

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

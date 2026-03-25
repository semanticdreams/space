(local Runtime (require :state-runtime))

(local TextInputDispatch
  {:text-input (fn [_ctx payload]
                 (Runtime.dispatch-text-input payload))})

(local TextEditingDispatch
  {:text-editing (fn [_ctx payload]
                   (Runtime.dispatch-text-editing payload))})

{:TextInputDispatch TextInputDispatch
 :TextEditingDispatch TextEditingDispatch}

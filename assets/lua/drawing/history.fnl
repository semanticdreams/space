(fn DrawingHistory []
  (var undo-stack [])
  (var redo-stack [])

  (fn clear-redo! []
    (set redo-stack []))

  (fn perform [_self command]
    (assert (and command command.apply command.revert)
            "DrawingHistory.perform requires command with :apply and :revert")
    (command:apply)
    (if command.noop?
        false
        (do
          (table.insert undo-stack command)
          (clear-redo!)
          command)))

  (fn undo [_self]
    (local command (table.remove undo-stack))
    (if command
        (do
          (command:revert)
          (table.insert redo-stack command)
          command)
        false))

  (fn redo [_self]
    (local command (table.remove redo-stack))
    (if command
        (do
          (command:apply)
          (table.insert undo-stack command)
          command)
        false))

  (fn can-undo? [_self]
    (> (length undo-stack) 0))

  (fn can-redo? [_self]
    (> (length redo-stack) 0))

  (fn clear [_self]
    (set undo-stack [])
    (set redo-stack []))

  {:perform perform
   :undo undo
   :redo redo
   :can-undo? can-undo?
   :can-redo? can-redo?
   :clear clear})

DrawingHistory

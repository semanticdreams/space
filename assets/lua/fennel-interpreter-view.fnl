(local {: Flex : FlexChild} (require :flex))
(local Input (require :input))
(local ListView (require :list-view))
(local Button (require :button))
(local Text (require :text))
(local FennelEvaluator (require :fennel-evaluator))
(local Modifiers (require :input-modifiers))
(local Utils (require :graph/view/utils))

(local SDLK_RETURN 13)

(fn trim-entries! [entries max-entries]
  (while (> (length entries) max-entries)
    (table.remove entries 1)))

(fn format-output-line [entry wrap-columns]
  (local prefix (or entry.prefix ""))
  (local content (or entry.content ""))
  (Utils.wrap-text (.. prefix content) wrap-columns))

(fn FennelInterpreterView [opts]
  (local options (or opts {}))

  (fn build [ctx]
    (local max-entries (math.max 1 (or options.max-entries 200)))
    (local wrap-columns (math.max 1 (or options.output-wrap-columns 100)))
    (local output-viewport-height (or options.output-viewport-height 14))
    (local output-reverse?
      (if (= options.output-reverse nil)
          true
          (not (not options.output-reverse))))
    (local input
      ((Input {:name (or options.input-name "fennel-interpreter-input")
               :focus-name (or options.input-focus-name "fennel-interpreter-input")
               :placeholder (or options.placeholder "Enter Fennel code. Ctrl+Enter to run.")
               :multiline? true
               :line-count (or options.line-count 8)})
       ctx))
    (local output
      ((ListView {:name (or options.output-name "fennel-interpreter-output")
                  :title (or options.output-title "")
                  :show-head false
                  :reverse output-reverse?
                  :scroll true
                  :paginate false
                  :viewport-height output-viewport-height
                  :items-per-page (or options.items-per-page 12)
                  :items []
                  :builder (fn [entry child-ctx]
                             ((Text {:text (format-output-line entry wrap-columns)}) child-ctx))})
       ctx))
    (var entries [])
    (local self {:layout nil
                 :input input
                 :output output
                 :entries entries})

    (fn push-entry [entry]
      (table.insert entries entry)
      (trim-entries! entries max-entries)
      (output:set-items entries)
      (when (and output-reverse? output.set-scroll-offset)
        (output:set-scroll-offset 0)))

    (fn run-source []
      (local source (input:get-text))
      (if (or (not source) (= source ""))
          false
          (do
            (push-entry {:prefix "> " :content source})
            (local result (FennelEvaluator.eval-source source))
            (if result.ok
                (push-entry {:prefix "< " :content (FennelEvaluator.format-result result.result)})
                (push-entry {:prefix "! " :content (FennelEvaluator.format-error result.result)}))
            (input:request-focus)
            true)))

    (fn clear-output []
      (set entries [])
      (set self.entries entries)
      (output:set-items entries)
      (input:request-focus)
      true)

    (fn clear-input []
      (input:set-text "")
      (input:request-focus)
      true)

    (local run-button
      (Button {:text "Run"
               :variant :primary
               :on-click (fn [_button _event]
                           (run-source))}))
    (local clear-output-button
      (Button {:text "Clear Output"
               :variant :secondary
               :on-click (fn [_button _event]
                           (clear-output))}))
    (local clear-input-button
      (Button {:text "Clear Input"
               :variant :secondary
               :on-click (fn [_button _event]
                           (clear-input))}))

    (local actions-row
      (Flex {:axis 1
             :xspacing 0.4
             :children [(FlexChild run-button 0)
                        (FlexChild clear-output-button 0)
                        (FlexChild clear-input-button 0)]}))
    (local root
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.5
              :children [(FlexChild actions-row 0)
                         (FlexChild (fn [_] output) 1)
                         (FlexChild (fn [_] input) 0)]})
       ctx))

    (local input-on-key-down input.on-key-down)
    (set input.on-key-down
         (fn [input-self payload]
           (if (and payload
                    (= payload.key SDLK_RETURN)
                    (Modifiers.ctrl-held? payload.mod))
               (run-source)
               (if input-on-key-down
                   (input-on-key-down input-self payload)
                   false))))

    (set self.layout root.layout)
    (set self.format-entry-line
         (fn [_self entry]
           (format-output-line entry wrap-columns)))
    (set self.run run-source)
    (set self.clear-output clear-output)
    (set self.clear-input clear-input)
    (set self.drop root.drop)
    self))

FennelInterpreterView

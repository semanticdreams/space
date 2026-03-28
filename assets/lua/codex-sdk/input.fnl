(fn normalize-input [input]
  (if (= (type input) :string)
      {:prompt input :images []}
      (do
        (when (not (= (type input) :table))
          (error "codex-sdk input must be a string or a table of input items"))
        (local prompt-parts [])
        (local images [])
        (each [_ item (ipairs input)]
          (when (not (= (type item) :table))
            (error "codex-sdk input items must be tables"))
          (if (= item.type :text)
              (do
                (when (not (= (type item.text) :string))
                  (error "codex-sdk text input requires string :text"))
                (table.insert prompt-parts item.text))
              (= item.type :local-image)
              (do
                (when (not (= (type item.path) :string))
                  (error "codex-sdk local-image input requires string :path"))
                (table.insert images item.path))
              (error (.. "codex-sdk unsupported input item type: " (tostring item.type)))))
        {:prompt (table.concat prompt-parts "\n\n")
         :images images})))

{:normalize-input normalize-input}

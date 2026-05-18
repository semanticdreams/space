;; Prompt utilities — context formatting, preset formatting, template rendering, enrichers.

(var enrichers {})

(fn register-enricher [name fn-impl]
  (assert (= (type name) "string") "enricher name must be a string")
  (assert (= (type fn-impl) "function") "enricher must be a function")
  (tset enrichers name fn-impl))

(fn remove-enricher [name]
  (tset enrichers name nil))

(fn format-context [ctx]
  (local parts [])
  (each [name enrich (pairs enrichers)]
    (local (ok result) (pcall enrich ctx))
    (if ok
        (when result
          (table.insert parts result))
        (error (.. "agent prompt enricher '" (tostring name) "' failed: "
                   (tostring result)))))
  (if (= (length parts) 0)
      "No active context."
      (table.concat parts "\n")))

(fn format-presets [presets]
  (local active (presets:get-active-presets))
  (if (= (length active) 0)
      "No active presets."
      (do
        (local lines ["Active presets:"])
        (local sorted [])
        (each [_ p (ipairs active)]
          (table.insert sorted p.name))
        (table.sort sorted)
        (each [_ name (ipairs sorted)]
          (each [_ p (ipairs active)]
            (when (= p.name name)
              (table.insert lines (.. "  " p.name " (" (tostring p.reason) ")")))))
        (table.concat lines "\n"))))

(fn render-placeholder [vars key]
  (local value (. (or vars {}) key))
  (if value (tostring value) (.. "${" key "}")))

(fn render-template [template vars]
  (assert (= (type template) "string") "template must be a string")
  (local result (template:gsub "%${([%w_]+)}"
                               (fn [key]
                                 (render-placeholder vars key))))
  result)

(fn assemble-blocks [blocks]
  (assert (= (type blocks) "table") "blocks must be a table")
  (local lines [])
  (each [_ block (ipairs blocks)]
    (when (and block.name block.content)
      (table.insert lines (.. "## " block.name))
      (table.insert lines block.content)
      (table.insert lines "")))
  (table.concat lines "\n"))

{:register-enricher register-enricher
 :remove-enricher remove-enricher
 :format-context format-context
 :format-presets format-presets
 :render-template render-template
 :assemble-blocks assemble-blocks}

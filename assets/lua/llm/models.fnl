(local json (require :json))
(local fs (require :fs))

(fn normalize-model-name [model]
  (if model
      (let [name (tostring model)
            stripped-date (string.match name "^(.-)%-%d%d%d%d%-%d%d%-%d%d$")
            stripped-suffix (string.match name "^(.-)%-%d%d%d%d$")]
        (or stripped-date stripped-suffix name))
      nil))

(var model-context-cache nil)

(fn load-model-context-window [model]
  (local name (normalize-model-name model))
  (when name
    (when (not model-context-cache)
      (set model-context-cache {}))
    (local cached (rawget model-context-cache name))
    (if (not (= cached nil))
        (if cached cached nil)
        (do
          (local path
            (and app app.engine app.engine.get-asset-path
                 (app.engine.get-asset-path (.. "data/openai/models/" name ".json"))))
          (if (not path)
              (do
                (set (. model-context-cache name) false)
                nil)
              (let [(ok content) (pcall fs.read-file path)]
                (if ok
                    (let [(parse-ok parsed) (pcall json.loads content)]
                      (if (and parse-ok parsed parsed.context_window)
                          (do
                            (set (. model-context-cache name) parsed.context_window)
                            parsed.context_window)
                          (do
                            (set (. model-context-cache name) false)
                            nil)))
                    (do
                      (set (. model-context-cache name) false)
                      nil))))))))

(fn context-window [model]
  (load-model-context-window model))

{:normalize-model-name normalize-model-name
 :context-window context-window}

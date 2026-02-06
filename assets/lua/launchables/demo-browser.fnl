(fn run []
  (local scene app.scene)
  (when (and scene scene.add-demo-browser)
    (scene:add-demo-browser)))

{:name "Demo Browser"
 :run run}

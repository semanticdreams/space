class LuaWorldApp:
    def __init__(self):
        self.obj = z.LuaWorldView()

        self.obj.layout.position = np.array((0, 0, -300), float)
        #self.obj.layout.rotation = transformations.quaternion_about_axis(
        #    math.pi * 0.5, (1, 0, 0))
        self.on_viewport_changed()
        self.obj.layout.layouter()

        world.viewport.changed.connect(self.on_viewport_changed)

    def on_viewport_changed(self):
        self.obj.layout.size = np.array((400, 400 * world.height/world.width, 0), float)
        self.obj.layout.mark_layout_dirty()
        self.obj.layout.layouter()

    def drop(self):
        self.obj.drop()

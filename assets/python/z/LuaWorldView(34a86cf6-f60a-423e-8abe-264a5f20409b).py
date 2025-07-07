class LuaWorldView:
    def __init__(self, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.layout = z.Layout(name='lua-world', measurer=self.measurer,
                               layouter=self.layouter)

    def measurer(self):
        self.layout.measure = np.array((10, 10, 0))

    def layouter(self):
        world.renderers.lua_world.update_quad(self.layout)

    def drop(self):
        self.layout.drop()
        self.focus.drop()

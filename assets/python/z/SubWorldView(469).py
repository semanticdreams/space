class SubWorldView:
    def __init__(self, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.layout = z.Layout(name='sub_world', measurer=self.measurer,
                               layouter=self.layouter)
        self.sub_world = SubWorld(self)
        world.renderers.sub_worlds.append(self.sub_world)

    def measurer(self):
        self.layout.measure = np.array((10, 10, 0))

    def layouter(self):
        self.sub_world.update_quad()

    def drop(self):
        world.renderers.sub_worlds.remove(self.sub_world)
        self.layout.drop()
        self.focus.drop()
class Worktop:
    def __init__(self, focus_parent=world.focus):
        self.rectangle = z.Button('button', background_color=(1, 1, 0, 1))
        self.right_pane = z.Flex([
            #z.FlexChild(self.rectangle.layout)
        ], axis='y', xalign='largest')

        self.layout = z.Layout(
            children=[self.right_pane.layout],
            name='worktop', measurer=self.measurer,
            layouter=self.layouter)

        self.active_pane = self.right_pane

    def add(self, obj):
        self.active_pane.layout.add_child(obj.layout)
        self.layout.mark_measure_dirty()

    def measurer(self):
        [x.measurer() for x in self.layout.children]
        self.layout.measure = np.array((0.0, 0.0, 0.0))

    def layouter(self):
        offset = np.array((self.layout.size[0] - self.layout.size[0] / 4, 0, 0))
        offset += world.camera.camera.position
        self.right_pane.layout.position = self.layout.position + offset
        self.right_pane.layout.rotation = self.layout.rotation.copy()
        self.right_pane.layout.size = np.array((
            self.layout.size[0] / 4,
            self.layout.size[1],
            self.layout.size[2]
        ))
        self.right_pane.layout.layouter()

    def drop(self):
        self.layout.drop()
        self.right_pane.drop()
        self.rectangle.drop()

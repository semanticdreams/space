class Bordered:
    def __init__(self, child, width=world.themes.theme.border_width, color=(1, 1, 1, 1), hud=False):
        self.hud = hud
        self.child = child
        self.width = width
        self.rectangle = Rectangle(color=color, hud=hud)
        self.layout = Layout(children=[self.rectangle.layout, self.child],
                             measurer=self.measurer, layouter=self.layouter, name='bordered')

    def set_color(self, color):
        self.rectangle.set_color(color)

    def measurer(self):
        self.child.measurer()
        self.layout.measure = self.child.measure.copy()
        self.layout.measure[:2] += self.width * 2

    def layouter(self):
        self.child.depth_offset_index = self.layout.depth_offset_index
        self.child.size = self.layout.size.copy()
        self.child.size[:2] -= self.width * 2
        self.child.position = self.layout.position.copy()
        offset = np.array((self.width, self.width, 0.01), float)
        self.child.position = self.layout.position + transformations.rotate_vector(self.layout.rotation, offset)
        self.child.rotation = self.layout.rotation
        self.child.layouter()
        self.rectangle.layout.size = self.layout.size
        self.rectangle.layout.position = self.layout.position
        self.rectangle.layout.rotation = self.layout.rotation
        self.rectangle.layout.layouter()

    def drop(self):
        self.layout.drop()
        self.rectangle.drop()

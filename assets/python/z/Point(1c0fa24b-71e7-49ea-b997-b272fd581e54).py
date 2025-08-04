class Point:
    def __init__(self, color=(1, 0, 1, 1), sub_color=None, size=10, pinned=False,
                 on_click=None, on_right_click=None, on_double_click=None):
        self.size = size
        self.hud = False
        self.pinned = pinned
        self.on_click = on_click or (lambda f, i, d: None)
        self.on_right_click = on_right_click or (lambda f, i, d: None)
        self.on_double_click = on_double_click or (lambda f, i, d: None)
        self.layout = z.Layout(measurer=self.measurer, layouter=self.layouter)
        self.rectangle = z.RRectangle(color=color, size=(size, size))
        self.rectangle2 = None
        if sub_color is not None:
            self.rectangle2 = z.RRectangle(color=sub_color, size=(size-1, size))
        world.apps['Clickables'].register(self)

    def intersect(self, ray):
        return self.layout.intersect(ray)

    def measurer(self):
        self.layout.measure = np.array((self.size, self.size, 0), float)

    def set_sub_color(self, color):
        if self.rectangle2:
            self.rectangle2.set_color(color)
            self.rectangle2.update_color()

    def layouter(self):
        self.rectangle.set_position(self.layout.position)
        self.rectangle.set_rotation(self.layout.rotation)
        self.rectangle.update()

        if self.rectangle2:
            self.rectangle2.set_position(self.layout.position \
                                         + np.array((1, 0, 0.05)))
            self.rectangle2.set_rotation(self.layout.rotation)
            self.rectangle2.update()

    def drop(self):
        world.apps['Clickables'].unregister(self)
        self.rectangle.drop()
        if self.rectangle2:
            self.rectangle2.drop()

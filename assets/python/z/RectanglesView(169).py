import gc
class RectanglesView:
    def __init__(self):
        items = [f'{np.round(x.layout.position)} {x.color.get()} {x.size}' for x in gc.get_objects() if isinstance(x, z.Rectangle)]

        self.focus = world.focus.add_child(self)
        self.list_view = z.ListView(items, focus_parent=self.focus, name='rectangles')

        self.layout = self.list_view.layout

    def drop(self):
        self.list_view.drop()
        self.focus.drop()
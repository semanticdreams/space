class WorldView:
    def __init__(self):
        self.focus = world.focus.add_child(self)
        self.button = z.ContextButton(
            label='world', color=(0.2, 0.4, 1, 1),
            focus_parent=self.focus,
            actions=[
                ('pyobj', lambda: world.floaties.add(z.PyObjView(world))),
            ])
        self.layout = self.button.layout

    def drop(self):
        self.button.drop()
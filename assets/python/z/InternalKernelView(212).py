class InternalKernelView:
    def __init__(self, kernel):
        self.kernel = kernel
        self.name = z.ReactiveValue(self.make_name())
        self.focus = world.focus.add_child(self)
        actions = [
            ('env', self.env_triggered),
        ]
        self.actions_panel = z.ActionsPanel(actions, self.focus)

        self.column = z.Flex(xalign='largest', axis='y', children=[
            z.FlexChild(self.actions_panel.layout),
        ])
        self.layout = self.column.layout

    def make_name(self):
        return f'kernel: {self.kernel.id} {self.kernel.name}'

    def env_triggered(self):
        world.floaties.add(world.classes.get_class(name='PyDictView')(self.kernel.env))

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.focus.drop()
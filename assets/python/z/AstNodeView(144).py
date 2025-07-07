class AstNodeView:
    def __init__(self, node):
        self.node = node

        self.focus = world.focus.add_child(self)

        self.button = z.ContextButton(
            label=str(self.node),
            focus_parent=self.focus,
            color=(0.6, 1.0, 0.4, 1),
            actions=[
                ('pyobj', lambda: world.floaties.add(z.PyObjView(self.node))),
            ]
        )

        self.layout = self.button.layout

    def get_name(self):
        return f'AstNode: {self.node}'

    def drop(self):
        self.button.drop()
        self.focus.drop()
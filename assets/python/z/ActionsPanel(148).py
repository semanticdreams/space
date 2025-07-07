class ActionsPanel:
    def __init__(self, actions, focus_parent):
        self.focus = focus_parent.add_child(self)

        self.buttons = []

        for name, func in actions:
            button = z.Button(name, focus_parent=self.focus)
            button.clicked.connect(lambda f, i, d, func=func: func())
            self.buttons.append(button)

        self.spacer = z.Spacer()

        self.row = z.Flex(children=[
            *[z.FlexChild(x.layout) for x in self.buttons],
            z.FlexChild(self.spacer.layout, flex=1)
        ], yalign='largest')

        self.layout = self.row.layout

    def drop(self):
        self.row.drop()
        self.spacer.drop()
        for button in self.buttons:
            button.drop()
        self.focus.drop()
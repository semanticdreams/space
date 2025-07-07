class ClipboardView:
    def __init__(self):
        self.focus = world.focus.add_child(self)
        self.name = z.ReactiveValue('Clipboard')
        self.actions_panel = z.ActionsPanel([
            ('reload', self.reload),
        ], focus_parent=self.focus)
        self.input = z.Input(text=world.apps['Clipboard'].get_text(), focus_parent=self.focus)
        self.input.submitted.connect(self.input_submitted)
        self.column = z.Flex([self.actions_panel, self.input],
                                     axis='y', xalign='largest')
        self.layout = self.column.layout

    def reload(self):
        self.input.set_text(world.apps['Clipboard'].get_text())

    def input_submitted(self):
        world.apps['Clipboard'].set_text(self.input.text)

    def drop(self):
        self.column.drop()
        self.input.drop()
        self.actions_panel.drop()

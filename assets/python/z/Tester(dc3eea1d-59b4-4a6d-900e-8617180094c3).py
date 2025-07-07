class Tester:
    def __init__(self, focus_parent=world.focus):
        self.focus = focus_parent.add_child(self)
        actions = [
            ('reset', self.reset),
            ('toggle', self.toggle),
        ]
        self.actions_panel = z.ActionsPanel(actions, focus_parent=self.focus)
        self.setup_code_input = z.Input(multiline=True, focus_parent=self.focus)
        self.teardown_code_input = z.Input(multiline=True, focus_parent=self.focus)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.setup_code_input.layout, flex=1),
            z.FlexChild(self.teardown_code_input.layout, flex=1),
        ], axis='y', xalign='largest')

        self.layout =  self.column.layout

        self.active = False

    def setup(self):
        code_str = self.setup_code_input.text
        world.kernels.ensure_kernel(0).send_code(dict(lang='py', code=code_str))
        self.active = True

    def teardown(self):
        code_str = self.teardown_code_input.text
        world.kernels.ensure_kernel(0).send_code(dict(lang='py', code=code_str))
        self.active = False

    def reset(self):
        self.teardown()
        self.setup()

    def toggle(self):
        if self.active:
            self.teardown()
        else:
            self.setup()

    def drop(self):
        self.column.drop()
        self.setup_code_input.drop()
        self.teardown_code_input.drop()
        self.actions_panel.drop()
        self.focus.drop()


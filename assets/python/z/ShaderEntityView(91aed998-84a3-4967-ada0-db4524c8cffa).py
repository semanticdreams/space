class ShaderEntityView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity

        self.actions_panel = z.ActionsPanel([
            ('delete', self.entity.delete),
            ('sys-copy', self.sys_copy_triggered),
        ], focus_parent=self.focus)

        self.name_input = z.Input(self.entity.name, focus_parent=self.focus)
        self.name_input.submitted.connect(self.name_input_submitted)

        self.code_input = z.Input(self.entity.code_str, multiline=True,
                                  tabs=True, focus_parent=self.focus,
                                  min_lines=3, max_lines=10, syntax_coloring=True)
        self.code_input.submitted.connect(self.code_input_submitted)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.name_input.layout),
            z.FlexChild(self.code_input.layout, flex=1)
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def sys_copy_triggered(self):
        world.apps['Clipboard'].set_text(self.entity.code_str)

    def code_input_submitted(self):
        self.entity.code_str = self.code_input.text
        self.entity.save()

    def name_input_submitted(self):
        self.entity.name = self.name_input.text
        self.entity.save()

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.name_input.drop()
        self.code_input.drop()
        self.focus.drop()

class WorkspaceView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity

        self.name_input =  z.Input(self.entity.name, focus_parent=self.focus)
        self.name_input.submitted.connect(self.name_input_submitted)

        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.entity.copy),
            ('delete', self.delete_triggered),
        ], focus_parent=self.focus)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.name_input.layout),
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def name_input_submitted(self):
        self.entity.name = self.name_input.text
        self.entity.save()

    def delete_triggered(self):
        self.entity.delete()

    def drop(self):
       self.column.drop()
       self.name_input.drop()
       self.actions_panel.drop()
       self.focus.drop()

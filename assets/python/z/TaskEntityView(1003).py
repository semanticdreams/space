class TaskEntityView:
    def __init__(self, entity, focus_parent=world.focus):
        self.focus = focus_parent.add_child(self)
        self.entity = entity

        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.entity.copy),
            ('delete', self.delete),
            ('toggle done', self.toggle_done),
        ], focus_parent=self.focus)

        self.label_input = z.Input(self.entity.label, multiline=True, tabs=True,
                                   min_lines=5, focus_parent=self.focus)
        self.label_input.submitted.connect(self.on_label_submitted)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.label_input.layout, flex=1)
        ], axis='y', xalign='largest')
        self.layout = self.column.layout

    def on_label_submitted(self):
        self.entity.label = self.label_input.text
        self.entity.save()

    def delete(self):
        self.entity.delete()

    def toggle_done(self):
        self.entity.set_done(False if self.entity.done_at else True)
        self.entity.save()

    def drop(self):
        self.column.drop()
        self.label_input.drop()
        self.actions_panel.drop()
        self.focus.drop()

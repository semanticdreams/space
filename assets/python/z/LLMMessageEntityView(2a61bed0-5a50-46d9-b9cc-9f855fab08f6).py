class LLMMessageEntityView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity

        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.entity.copy),
            ('delete', self.entity.delete),
        ], focus_parent=self.focus)

        self.role_input = z.Input(self.entity.role, focus_parent=self.focus)
        self.role_input.submitted.connect(self.on_role_submitted)
        self.content_input = z.Input(self.entity.content, focus_parent=self.focus,
                                     multiline=True)
        self.content_input.submitted.connect(self.on_content_submitted)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.role_input.layout),
            z.FlexChild(self.content_input.layout, flex=1),
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def on_role_submitted(self):
        role = self.role_input.text
        assert role in ('system', 'assistant', 'user')
        self.entity.role = role
        self.entity.save()

    def on_content_submitted(self):
        self.entity.content = self.content_input.text
        self.entity.save()

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.role_input.drop()
        self.content_input.drop()
        self.focus.drop()

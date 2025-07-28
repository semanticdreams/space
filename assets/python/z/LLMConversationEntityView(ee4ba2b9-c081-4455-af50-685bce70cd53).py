class LLMConversationEntityView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity

        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.entity.copy),
            ('delete', self.entity.delete),
            ('send', self.entity.send),
        ], focus_parent=self.focus)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.focus.drop()

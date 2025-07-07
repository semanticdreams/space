class FloatEntityView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity

        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.entity.copy),
            ('delete', self.entity.delete),
        ], focus_parent=self.focus)

        val = self.entity.get_value()
        self.input = z.Input('' if val is None else str(val), focus_parent=self.focus)
        self.input.submitted.connect(self.on_input_submitted)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.input.layout, flex=1)
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def __str__(self):
        return str(self.entity)

    def on_input_submitted(self):
        try:
            val = float(self.input.text)
        except:
            val = None
        self.entity.set_value(val)
        self.input.set_text('' if val is None else str(val))

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.input.drop()
        self.focus.drop()


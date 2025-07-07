class TagEntityView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity

        # Actions
        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.entity.copy),
            ('paste target entity', self.paste_target),
        ], focus_parent=self.focus)

        # Tag input
        self.tag_label = z.Label("Tag:")
        self.input = z.Input(self.entity.get_tag() or '', focus_parent=self.focus)
        self.input.submitted.connect(self.on_input_submitted)

        # Target display
        self.target_label = z.Label("Target:")
        if self.entity.target_entity_id is not None:
            target = self.entity.get_target_entity()
            self.target_preview = target.preview(target, focus_parent=self.focus)
        else:
            self.target_preview = z.Label('<no target>')

        # Layout
        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.tag_label.layout),
            z.FlexChild(self.input.layout),
            z.FlexChild(self.target_label.layout),
            z.FlexChild(self.target_preview.layout, flex=1)
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def __str__(self):
        return str(self.entity)

    def on_input_submitted(self):
        self.entity.set_tag(self.input.text or None)
        self.input.set_text(self.entity.get_tag() or '')

    def paste_target(self):
        assert Y.register_type == 'entity'
        entity = Y.value
        self.entity.target_entity_id = entity.id
        self.entity.save()

        self.target_preview.drop()
        self.target_preview = entity.preview(entity, focus_parent=self.focus)
        self.column.set_children([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.tag_label.layout),
            z.FlexChild(self.input.layout),
            z.FlexChild(self.target_label.layout),
            z.FlexChild(self.target_preview.layout, flex=1)
        ])

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.input.drop()
        self.tag_label.drop()
        self.target_label.drop()
        self.target_preview.drop()
        self.focus.drop()


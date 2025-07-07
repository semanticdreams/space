class EntityMorphView:
    def __init__(self, focus_parent=world.focus):
        self.focus = focus_parent.add_child(self)
        self.actions_panel = z.ActionsPanel([
            ('paste source entity', self.paste_source_entity_triggered),
        ], focus_parent=self.focus)
        self.entity_label = z.Label()
        self.search_view = z.SearchView([], focus_parent=self.focus)
        self.search_view.submitted.connect(self.on_submitted)
        self.result_entity_label = z.Label()
        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.entity_label.layout),
            z.FlexChild(self.search_view.layout, flex=1),
            z.FlexChild(self.result_entity_label.layout),
        ], axis='y', xalign='largest')
        self.layout = self.column.layout

        self.source_entity = None
        self.result_entity = None

    def paste_source_entity_triggered(self):
        self.result_entity_label.set_text('')
        assert Y.register_type == 'entity', Y.register_type
        self.source_entity = Y.value
        self.entity_label.set_text(str(self.source_entity))
        morphs = world.apps['Entities'].morphs.get(self.source_entity.type, [])
        self.search_view.set_items([(x, x[0]) for x in morphs])

    def on_submitted(self, item):
        target_type, morph_cls = item[0]
        self.result_entity = morph_cls(self.source_entity)()
        self.result_entity_label.set_text(str(self.result_entity))

    def drop(self):
        self.column.drop()
        self.search_view.drop()
        self.actions_panel.drop()
        self.entity_label.drop()
        self.result_entity_label.drop()
        self.focus.drop()

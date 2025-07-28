class CreateEntityMorphView:
    def __init__(self, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)

        self.name_input = z.Input(focus_parent=self.focus)
        self.submit_button = z.Button('submit', focus_parent=self.focus)
        self.submit_button.clicked.connect(self.on_submit_clicked)
        self.row = z.Flex([
            z.FlexChild(self.name_input.layout, flex=1),
            z.FlexChild(self.submit_button.layout)
        ], yalign='largest')
        self.layout = self.row.layout

    def on_submit_clicked(self, f, i, d):
        name = self.name_input.text
        print('creating morph', name)
        assert name, name
        code_str = f"""class {name}:
    def __init__(self, source_entity):
        self.source_entity = source_entity

    def __call__(self):
        new_entity = ...
        self.source_entity.delete()
        new_entity.update_id(self.source_entity.id)
        return new_entity"""
        cls_entity = z.ClassEntity.create(
            name=name, code_str=code_str)
        G.add_node(cls_entity)
        G.add_edge(z.Entity.get('484daa69-b42b-4b29-aa37-bf926b668342'), cls_entity)
        G.save()
        print('done')

    def drop(self):
        self.row.drop()
        self.name_input.drop()
        self.submit_button.drop()
        self.focus.drop()

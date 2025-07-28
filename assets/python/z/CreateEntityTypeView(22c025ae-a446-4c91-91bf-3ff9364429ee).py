class CreateEntityTypeView:
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
        assert name, name
        entity_cls_name = f'{name}Entity'
        if entity_cls_name in world.classes.names:
            raise Exception(f'Entity class {entity_cls_name} exists')
        view_cls_name = f'{entity_cls_name}View'
        preview_cls_name = f'{entity_cls_name}Preview'
        color = util.random_color()
        entity_type_name = util.camel_to_hyphen(name)
        code_str = f"""class {entity_cls_name}(z.Entity):
    def __init__(self, id, value):
        super().__init__('{entity_type_name}', id)
        self.value = value
        self.view = z.{view_cls_name}
        self.preview = z.{preview_cls_name}
        self.color = {color.tolist()}

    @classmethod
    def create(cls, value=None, id=None):
        id = super().create('{entity_type_name}', value, id=id)
        return cls(id, value)

    @classmethod
    def load(cls, id, data):
        return cls(id, data)

    def clone(self):
        return {entity_cls_name}.create(value=self.value)

    def dump_data(self):
        return self.value
"""
        view_code_str = f"""class {view_cls_name}:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity

        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.entity.copy),
            ('delete', self.entity.delete),
        ], focus_parent=self.focus)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.focus.drop()
"""
        preview_code_str = f"""class {preview_cls_name}:
    def __init__(self, entity, focus_parent=None):
        self.entity = entity
        self.button = z.ContextButton(
            label='{entity_type_name}',
            focus_parent=focus_parent,
            max_lines=1,
            font_scale=5,
            actions=[
                ('view', lambda: world.floaties.add(
                    self.entity.view(self.entity))),
            ]
        )
        self.layout = self.button.layout

    def drop(self):
        self.button.drop()
"""
        cls_entity = z.ClassEntity.create(name=entity_cls_name, code_str=code_str)
        view_entity = z.ClassEntity.create(name=view_cls_name, code_str=view_code_str)
        preview_entity = z.ClassEntity.create(
            name=preview_cls_name, code_str=preview_code_str)
        G.add_node(cls_entity)
        G.add_node(view_entity)
        G.add_node(preview_entity)
        G.add_edge(cls_entity, view_entity)
        G.add_edge(cls_entity, preview_entity)
        G.add_edge(z.ClassEntity.find('Entities'), cls_entity)
        G.add_edge(z.Entity.get('f403458d-968a-4818-8740-433413527e3f'), view_entity)
        G.add_edge(z.Entity.get('7dea25a5-7c49-4e82-9f0b-3830ececfd4b'), preview_entity)
        G.save()

    def drop(self):
        self.row.drop()
        self.name_input.drop()
        self.submit_button.drop()
        self.focus.drop()

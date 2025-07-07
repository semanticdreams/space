class DictEntityView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity

        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.entity.copy),
            ('delete', self.entity.delete),
            ('paste key entity', self.paste_triggered),
        ], focus_parent=self.focus)

        self.pairs_column = z.Flex([], axis='y', xalign='largest')
        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.pairs_column.layout, flex=1)
        ], axis='y', xalign='largest')

        self.layout = self.column.layout
        self.objs = []
        self.update_items()

    def __str__(self):
        return str(self.entity)

    def update_items(self):
        self.drop_objs()
        for item in self.entity.dict_items:
            key = world.apps['Entities'].get_entity(item['key_entity_id'])
            value = world.apps['Entities'].get_entity(item['value_entity_id']) if item['value_entity_id'] is not None else None
            obj = z.DictEntityViewChild(self, key, value, focus_parent=self.focus)
            self.objs.append(obj)
        self.pairs_column.set_children([z.FlexChild(o.layout) for o in self.objs])

    def drop_objs(self):
        self.pairs_column.clear_children()
        for obj in self.objs:
            obj.drop()
        self.objs.clear()

    def paste_triggered(self):
        assert Y.register_type == 'entity'
        key = Y.value
        self.entity.add_dict_item(key, None)
        self.update_items()

    def remove_pair(self, key_entity):
        self.entity.remove_dict_item(key_entity)
        self.update_items()

    def set_pair_value(self, key_entity, value_entity):
        with world.db:
            world.db.execute(
                'update dict_items set value_entity_id = ? where dict_id = ? and key_entity_id = ?',
                (value_entity.id, self.entity.item_id, key_entity.id)
            )
        for item in self.entity.dict_items:
            if item['key_entity_id'] == key_entity.id:
                item['value_entity_id'] = value_entity.id
        self.update_items()

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.pairs_column.drop()
        self.drop_objs()
        self.focus.drop()


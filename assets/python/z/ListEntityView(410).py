class ListEntityView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity
        assert isinstance(self.entity.id, str)
        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.copy_triggered),
            ('delete', self.entity.delete),
            ('paste entity as list item', self.paste_triggered),
        ], focus_parent=self.focus)

        self.objs = []
        self.items_column = z.Flex([], axis='y', xalign='largest')

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.items_column.layout, flex=1)
        ], axis='y', xalign='largest')
        self.layout = self.column.layout

        self.update_items()

    def __str__(self):
        return str(self.entity)

    def copy_triggered(self):
        Y(self.entity, 'entity')

    def drop_objs(self):
        self.items_column.clear_children()
        for obj in self.objs:
            obj.drop()
        self.objs.clear()

    def remove_item(self, entity):
        self.entity.remove_list_item(entity.id)
        self.update_items()

    def move_item_up(self, entity):
        items = self.entity.list_items
        item = one([x for x in items if x['entity_id'] == entity.id])
        lower_items = [x for x in items
                        if x['pos'] < item['pos']]
        if lower_items:
            max_lower_item = max(lower_items, key=lambda x: x['pos'])
            a, b = item['pos'], max_lower_item['pos']
            self.entity.set_list_item_pos(max_lower_item['entity_id'], a)
            self.entity.set_list_item_pos(item['entity_id'], b)
            self.update_items()

    def move_item_down(self, entity):
        items = self.entity.list_items
        item = one([x for x in items if x['entity_id'] == entity.id])
        higher_items = [x for x in items
                        if x['pos'] > item['pos']]
        if higher_items:
            min_higher_item = min(higher_items, key=lambda x: x['pos'])
            a, b = item['pos'], min_higher_item['pos']
            self.entity.set_list_item_pos(min_higher_item['entity_id'], a)
            self.entity.set_list_item_pos(item['entity_id'], b)
            self.update_items()

    def update_items(self):
        self.drop_objs()
        for item in self.entity.list_items:
            try:
                entity = world.apps['Entities'].get_entity(item)
            except z.EntityNotFoundError:
                self.entity.remove_list_item(item)
                self.entity.save()
                continue
            obj = z.ListEntityViewChild(self, entity, focus_parent=self.focus)
            self.objs.append(obj)
        self.items_column.set_children([z.FlexChild(x.layout) for x in self.objs])

    def paste_triggered(self):
        assert Y.register_type == 'entity', Y.register_type
        entity = Y.value
        self.entity.add_list_item(entity)
        self.update_items()

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.items_column.drop()
        self.drop_objs()
        self.focus.drop()

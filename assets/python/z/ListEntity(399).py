class ListEntity(z.Entity):
    def __init__(self, id, list_items):
        self.list_items = list_items
        super().__init__('list', id)

        self.view = z.ListEntityView
        self.preview = z.ListEntityPreview
        self.color = (0.1, 0.5, 0.1, 1)

    def add_list_item(self, entity):
        self.list_items.append(entity.id)

    def remove_list_item(self, entity_id):
        self.list_items = [x for x in self.list_items if x != entity_id]

    @classmethod
    def create(cls):
        id = super().create('int')
        return cls(id, [])

    @classmethod
    def load(cls, id, data):
        return cls(id, [str(x) for x in data['items']])

    def dump_data(self):
        return {
                'items': self.list_items
        }

    def clone(self):
        new_list = ListEntity.create()
        for item in self.list_items:
            entity = world.apps['Entities'].get_entity(item['entity_id'])
            new_list.add_list_item(entity)
        return new_list

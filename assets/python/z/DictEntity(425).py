class DictEntity(z.Entity):
    def __init__(self, id, dict_items):
        self.dict_items = dict_items  # list of dicts: {'key_entity_id': ..., 'value_entity_id': ...}
        super().__init__('dict', id)

        self.view = z.DictEntityView
        self.preview = z.DictEntityPreview
        self.color = (0.1, 0.5, 0.1, 1)

    def add_dict_item(self, key_entity, value_entity):
        self.dict_items.append({
            'key_entity': key_entity,
            'value_entity': value_entity,
            'key_entity_id': key_entity.id,
            'value_entity_id': value_entity.id if value_entity else None
        })

    def remove_dict_item(self, key_entity):
        self.dict_items = [item for item in self.dict_items if item['key_entity_id'] != key_entity.id]

    @classmethod
    def create(cls):
        id = super().create('dict')
        return cls(id, [])

    @classmethod
    def load(cls, id, data):
        return cls(id, data['items'])

    def dump_data(self):
        return {
                'items': [[x['key_entity_id'], x['value_entity_id']]
                          for x in self.dict_items]}

    def clone(self):
        new_dict = DictEntity.create()
        for item in self.dict_items:
            key_entity = world.apps['Entities'].get_entity(item['key_entity_id'])
            value_entity = (world.apps['Entities'].get_entity(item['value_entity_id'])
                            if item['value_entity_id'] is not None else None)
            new_dict.add_dict_item(key_entity, value_entity)
        return new_dict


class Dict2JsonEntityMorph:
    def __init__(self, source_entity):
        self.source_entity = source_entity

    def __call__(self):
        entities = world.apps['Entities']
        data = {}
        for item in self.source_entity.dict_items:
            key_entity = entities.get_entity(item['key_entity_id'])
            value_entity = entities.get_entity(item['value_entity_id'])
            data[key_entity.value] = value_entity.value
        json_entity = z.JsonEntity.create(data)
        self.source_entity.delete()
        json_entity.update_id(self.source_entity.id)
        return json_entity

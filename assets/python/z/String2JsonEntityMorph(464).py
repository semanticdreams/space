class String2JsonEntityMorph:
    def __init__(self, source_entity):
        self.source_entity = source_entity

    def __call__(self):
        json_entity = z.JsonEntity.create(self.source_entity.value)
        self.source_entity.delete()
        json_entity.update_id(self.source_entity.id)
        return json_entity

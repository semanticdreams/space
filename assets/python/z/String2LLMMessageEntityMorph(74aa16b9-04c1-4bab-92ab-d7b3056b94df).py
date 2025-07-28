class String2LLMMessageEntityMorph:
    def __init__(self, source_entity):
        self.source_entity = source_entity

    def __call__(self):
        new_entity = z.LLMMessageEntity.create(
            content=self.source_entity.value, role='user')
        self.source_entity.delete()
        new_entity.update_id(self.source_entity.id)
        return new_entity
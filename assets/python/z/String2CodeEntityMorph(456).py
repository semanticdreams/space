class String2CodeEntityMorph:
    def __init__(self, source_entity):
        self.source_entity = source_entity

    def __call__(self):
        code_entity = z.CodeEntity.create(code_str=self.source_entity.value)
        self.source_entity.delete()
        code_entity.update_id(self.source_entity.id)
        return code_entity

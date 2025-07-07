class String2TaskEntityMorph:
    def __init__(self, source_entity):
        self.source_entity = source_entity

    def __call__(self):
        task_entity = z.TaskEntity.create(self.source_entity.value)
        self.source_entity.delete()
        task_entity.update_id(self.source_entity.id)

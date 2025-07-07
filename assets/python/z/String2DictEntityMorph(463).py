class String2DictEntityMorph:
    def __init__(self, source_entity):
        self.source_entity = source_entity

    def __call__(self):
        dict_entity = z.DictEntity.create()
        dict_entity.add_dict_item(z.StringEntity.create('text'),
                                  z.StringEntity.create(self.source_entity.value))
        self.source_entity.delete()
        dict_entity.update_id(self.source_entity.id)
        return dict_entity

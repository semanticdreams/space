class SpatialEntity(z.Entity):
    def __init__(self, id, target_entity_id, position, rotation):
        self.target_entity_id = target_entity_id
        self.position = np.asarray(position, float)
        self.rotation = np.asarray(rotation, float)
        super().__init__('spatial', id)

        self.view = z.SpatialEntityView
        self.preview = z.SpatialEntityPreview

    @classmethod
    def create(cls, target_entity_id):
        id = super().create('spatial')
        return cls(id, target_entity_id, (0, 0, 0), (1, 0, 0, 0))

    @classmethod
    def load(cls, id, data):
        return cls(id, data['target_entity_id'], data['position'], data['rotation'])

    def dump_data(self):
        return {'position': self.position.tolist(), 'rotation': self.rotation.tolist(),
                'target_entity_id': self.target_entity_id}

    def clone(self):
        e = SpatialEntity.create(self.target_entity_id)
        e.position = self.position
        e.rotation = self.rotation
        e.save()
        return e

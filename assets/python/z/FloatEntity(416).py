class FloatEntity(z.Entity):
    def __init__(self, id, value):
        self.value = value
        super().__init__('float', id)

        self.view = z.FloatEntityView
        self.preview = z.FloatEntityPreview
        self.color = (0.1, 0.5, 0.1, 1)

    def set_value(self, value):
        self.value = value
        self.save()

    def get_value(self):
        return self.value

    @classmethod
    def create(cls, value=None):
        id = super().create('float', data=value)
        return cls(id, value)

    @classmethod
    def load(cls, id, data):
        return cls(id, data)

    def dump_data(self):
        return self.value

    def clone(self):
        return FloatEntity.create(value=self.value)

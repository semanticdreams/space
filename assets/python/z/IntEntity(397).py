class IntEntity(z.Entity):
    def __init__(self, id, value):
        self.value = value
        super().__init__('int', id)

        self.view = z.IntEntityView
        self.preview = z.IntEntityPreview
        self.color = (0.1, 0.5, 0.1, 1)

    def set_value(self, value):
        self.value = value
        self.save()

    def get_value(self):
        return self.value

    @classmethod
    def create(cls, value=None):
        id = super().create('int', data=value)
        return cls(id, value)

    @classmethod
    def load(cls, id, data):
        return cls(id, data)

    def dump_data(self):
        return self.value

    def clone(self):
        return IntEntity.create(value=self.value)

class StringEntity(z.Entity):
    def __init__(self, id, value):
        super().__init__('string', id)
        self.value = value
        self.label = self.value

        self.view = z.StringEntityView
        self.preview = z.StringEntityPreview
        self.color = (0.1, 0.5, 0.1, 1)

    def set_value(self, value):
        self.value = value
        self.label = self.value
        self.save()

    def get_value(self):
        return self.value

    @classmethod
    def create(cls, value=None):
        id = super().create('string', data=value)
        return cls(id, value)

    @classmethod
    def load(cls, id, data):
        return cls(id, data)

    def dump_data(self):
        return self.value

    def clone(self):
        return StringEntity.create(value=self.value)


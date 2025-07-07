import json

class JsonEntity(z.Entity):
    def __init__(self, id, data):
        super().__init__('json', id)
        self.data = data  # This is a Python object (dict, list, etc.)
        self.label = str(data)

        self.view = z.JsonEntityView
        self.preview = z.JsonEntityPreview
        self.color = (0.1, 0.5, 0.1, 1)

    def set_data(self, data):
        self.data = data
        self.save()

    def get_data(self):
        return self.data

    @classmethod
    def create(cls, data=None):
        id = super().create('json', data=data)
        return cls(id, data)

    @classmethod
    def load(cls, id, data):
        return cls(id, data)

    def dump_data(self):
        return self.data

    def clone(self):
        return JsonEntity.create(data=self.data)

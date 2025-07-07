class TagEntity(z.Entity):
    def __init__(self, id, tag):
        self.tag = tag
        super().__init__('tag', id)

        self.view = z.TagEntityView
        self.preview = z.TagEntityPreview

    @classmethod
    def create(cls, tag=None):
        id = super().create('tag', data=tag)
        return cls(id, tag)

    @classmethod
    def load(cls, id, data):
        return cls(id, data)

    def dump_data(self):
        return self.tag

    def clone(self):
        return TagEntity.create(tag=self.tag)

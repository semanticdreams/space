class CanvasEntity(z.Entity):
    def __init__(self, id):
        super().__init__('canvas', id)

        self.view = z.CanvasEntityView
        self.preview = z.CanvasEntityPreview

    @classmethod
    def create(cls):
        pass

    @classmethod
    def load(cls, id, data):
        pass

    def clone(self):
        pass

    def dump_data(self):
        pass

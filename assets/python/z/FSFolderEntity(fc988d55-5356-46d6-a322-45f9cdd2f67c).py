class FSFolderEntity(z.Entity):
    def __init__(self, id, path, base=None):
        super().__init__('fs-folder', id)
        self.path = path
        self.base = base
        self.update_label()

        self.view = z.FSFolderEntityView
        self.preview = None
        self.color = (0.4, 0.4, 0.4, 1)

    def update_label(self):
        self.label = (self.base + ':' if self.base else '') + self.path

    def set_path(self, path):
        self.path = path
        self.update_label()
        self.save()

    def set_base(self, base):
        self.base = base
        self.update_label()
        self.save()

    def get_path(self):
        return self.path

    def get_full_path(self):
        if self.base is None:
            return self.path
        elif self.base == 'assets':
            return os.path.join(world.assets_path, self.path)
        else:
            raise Exception(f'unknown base: {self.base}')

    @classmethod
    def create(cls, path=None, base=None):
        id = super().create('fs-folder', data={'path': path, 'base': base})
        return cls(id, path)

    @classmethod
    def load(cls, id, data):
        return cls(id, data['path'], data['base'])

    def dump_data(self):
        return {'path': self.path, 'base': self.base}

    def clone(self):
        return FSFolderEntity.create(path=self.path, base=self.base)

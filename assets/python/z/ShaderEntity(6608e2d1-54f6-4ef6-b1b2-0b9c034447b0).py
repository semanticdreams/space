class ShaderEntity(z.Entity):
    def __init__(self, id, code_str, name):
        super().__init__('shader', id)
        self.code_str = code_str
        self.name = name
        self.label = self.name

        self.view = None
        self.preview = None
        self.color = (1.0, 0.2, 1.0, 1)

    @classmethod
    def create(cls, name='', code_str='', id=None):
        id = super().create(
            'shader',
            {'name': name, 'code_str': code_str}, id=id)
        return cls(id, code_str, name)

    @classmethod
    def load(cls, id, data):
        return cls(id, data['code_str'], data['name'])

    @classmethod
    def all(cls):
        return world.apps['Entities'].get_entities('shader')

    def clone(self):
        return ShaderEntity.create(
            name=self.name,
            code_str=self.code_str
        )

    def dump_data(self):
        return {
            'code_str': self.code_str,
            'name': self.name}

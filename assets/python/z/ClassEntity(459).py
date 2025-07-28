import os
class ClassEntity(z.Entity):
    def __init__(self, id, code_str, name=''):
        super().__init__('class', id)
        self.code_str = code_str
        self.name = name
        self.label = self.name

        self.view = z.ClassEntityView
        self.preview = z.ClassEntityPreview
        self.color = (0.5, 0.1, 0.1, 1)

    @classmethod
    def create(cls, name='', code_str='', id=None):
        id = super().create('class', {'name': name, 'code_str': code_str}, id=id)
        o = cls(id, code_str, name)
        o.save_to_file()
        return o

    @classmethod
    def load(cls, id, data):
        return cls(id, data['code_str'], data['name'])

    @classmethod
    def all(cls):
        return world.apps['Entities'].get_entities('class')

    @classmethod
    def find(cls, name):
        entity = world.apps['Entities'].get_entity(
            world.classes.names[name]['id'])
        return entity

    def clone(self):
        return ClassEntity.create(
            name=self.name,
            code_str=self.code_str
        )

    def dump_data(self):
        return {
            'code_str': self.code_str,
            'name': self.name
        }

    def save(self, to_file=True):
        super().save()
        if to_file:
            self.save_to_file()

    def save_to_file(self, reload_world_classes=True):
        path = os.path.join(world.assets_path, 'python/z',
                            f'{self.name}({self.id}).py')
        with open(path, 'w') as f:
            f.write(self.code_str)
        if reload_world_classes:
            world.classes.reload()

    def delete(self):
        super().delete()
        path = os.path.join(world.assets_path, 'python/z',
                            f'{self.name}({self.id}).py')
        os.remove(path)
        world.classes.reload()

    def eval(self):
        env = {}
        exec(self.code_str, env)
        return env.pop(self.name)

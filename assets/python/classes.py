import time
import os


class Classes:
    def __init__(self):
        self.reload()

    def reload(self):
        rows = world.db.execute(
            'select * from entities where type = "class"').fetchall()

        self.codes, self.names = {}, {}
        for row in rows:
            data = json.loads(row['data'])
            self.codes[row['id']] = {
                'code': data['code_str'],
                'name': data['name'],
                'lang': 'py',
                'id': row['id'],
                'kernel': 0,
                'project_id': 1,
            }
            self.names[data['name']] = self.codes[row['id']]
        self.classes = {}

    def load_class(self, id):
        code = self.codes[id]
        assert code['kernel'] == 0 # just assume internal kernel to keep things simple for now
        kernel = world.kernels.ensure_kernel(code['kernel'])
        result = kernel.send_code(code, catch_errors=True)
        assert not result['error'], result['error']
        if output := result['output'].strip():
            print(output)
        self.classes[id] = cls = kernel.env.pop(code['name'])
        return cls

    def get_class_code(self, id=None, name=None):
        if name:
            return self.names[name]
        return self.codes[id]

    def get_class(self, id=None, name=None):
        if name:
            code = self.names[name]
            if code['id'] not in self.classes:
                self.load_class(code['id'])
            return self.classes[code['id']]
        if id not in self.classes:
            self.load_class(id)
        return self.classes[id]

    def __getitem__(self, key):
        return self.get_class(name=key)

    def __contains__(self, key):
        return key in self.names

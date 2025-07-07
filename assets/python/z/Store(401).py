class Store:
    def __init__(self):
        self.data = {}
        self.data['registers'] = {'default': None}
        self.data['register_types'] = {'default': None}

    def __getitem__(self, key):
        return self.data[key]

    def __setitem__(self, key, value):
        self.data[key] = value

    def drop(self):
        self.data.clear()

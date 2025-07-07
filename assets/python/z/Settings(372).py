class Settings:
    def __init__(self):
        self.values = {}
        self.load_values()

    def load_values(self):
        with world.db:
            result = world.db.execute('select * from settings').fetchall()
        self.values = {x['key']: x['value'] for x in result}

    def set_value(self, key, value):
        self.values[key] = value
        with world.db:
            world.db.execute('replace into settings (key, value) values (?, ?)',
                             (key, value))

    def get_value(self, key):
        return self.values.get(key)
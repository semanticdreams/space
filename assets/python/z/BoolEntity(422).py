class BoolEntity(z.Entity):
    def __init__(self, bool_id, value):
        self.value = value
        super().__init__('bool', bool_id)

        self.view = z.BoolEntityView
        self.preview = z.BoolEntityPreview

    def set_value(self, value):
        self.value = bool(value)
        self.save()

    def get_value(self):
        return self.value

    @classmethod
    def create(cls, value=None):
        with world.db:
            cur = world.db.execute('insert into bools (value) values (?)',
                                   (1 if value else 0,))
            id = cur.lastrowid
        return cls(bool_id=id, value=bool(value))

    @classmethod
    def load(cls, item_id):
        row = one(world.db.execute(
            'select value from bools where id = ?', (item_id,)
        ).fetchall())[0]
        return cls(bool_id=item_id, value=bool(row))

    def dump_data(self):
        return self.value

    def clone(self):
        return BoolEntity.create(value=self.value)


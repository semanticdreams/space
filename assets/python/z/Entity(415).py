import json


class Entity:
    def __init__(self, type, id):
        self.type = type
        #self.item_id = item_id
        self.id = id
        #self.id = world.apps['Entities'].ensure_entity(type, item_id)['id']
        self.label = None
        self.color = np.asarray((0.2, 0.2, 0.4, 1))
        self.changed = z.Signal()

    @classmethod
    def get(cls, id):
        return world.apps['Entities'].get_entity(id)

    @classmethod
    def create(cls, type, data, id=None):
        return world.apps['Entities'].create_entity(type, data=json.dumps(data), id=id)

    def save(self, emit_changed=True):
        with world.db:
            world.db.execute('update entities set type = ?, data = ?, updated_at = ? where id = ?',
                             (self.type, json.dumps(self.dump_data()), time.time(), self.id))
        if emit_changed:
            self.changed.emit()

    def __init_subclass__(cls, **kwargs):
        super().__init_subclass__(**kwargs)

        assert 'dump_data' in cls.__dict__
        #assert 'save' not in cls.__dict__
        #assert 'delete' not in cls.__dict__

    def __str__(self):
        return '{}: {}'.format(self.type, self.id)

    def update_id(self, id):
        world.apps['Entities'].update_id(self.id, id)
        self.id = id

    def delete(self):
        world.apps['Entities'].delete_entity(self.id)

    def copy(self):
        Y(self, 'entity')

class TaskEntity(z.Entity):
    def __init__(self, id, label, points, parent, done_at):
        super().__init__('task', id)
        self.label = label or ''
        self.points = points
        self.parent = parent
        self.done_at = done_at

        self.view = z.TaskEntityView
        self.preview = z.TaskEntityPreview
        self.update_color()

    def update_color(self):
        if self.done_at:
            self.color = (0.3, 0.3, 0.1, 1)
        else:
            self.color = (0.8, 0.8, 0, 1)

    def set_done(self, done):
        if done:
            self.done_at = time.time()
        else:
            self.done_at = None
        self.update_color()
        self.changed.emit()

    @classmethod
    def create(cls, label='', points=10, parent=None, done_at=None):
        id = super().create('task', data=dict(label=label, points=points, parent=parent,
                                             done_at=done_at))
        return cls(id, label, points, parent, done_at)

    @classmethod
    def load(cls, id, data):
        return cls(id, data['label'], data['points'], data['parent'], data.get('done_at'))

    def dump_data(self):
        return dict(label=self.label, points=self.points, parent=self.parent,
                    done_at=self.done_at)

    def clone(self):
        return TaskEntity.create(label=self.labele, points=self.points,
                                 parent=self.parent, done_at=self.done_at)

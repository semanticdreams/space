class Workspaces(z.Entity):
    def __init__(self, id=None, data=None):
        if id is None:
            id = '1314fdbf-b233-416a-b1f9-af14e104d098'
        if data is None:
            data = json.loads(one(world.db.execute(
                'select data from entities where id = ?',
                (id,)
            ).fetchall())['data'])

        super().__init__('workspaces', id)

        self.data = data

        self.workspaces = {x.name: x for x in
                           world.apps['Entities'].get_entities('workspace')}

        self.active_workspace = None

        self.workspace_changed = z.Signal()

        self.set_workspace(self.data['active_workspace'])

    @classmethod
    def load(cls, id, data):
        return cls(id, data)

    def dump_data(self):
        return {'active_workspace': self.active_workspace.name if self.active_workspace else None}


    def set_workspace(self, name):
        if self.active_workspace and name == self.active_workspace.name:
            return
        old = None
        if self.active_workspace:
            self.active_workspace.deactivate()
            old = self.active_workspace
        if name:
            workspace = self.workspaces[name]
            workspace.activate()
        else:
            workspace = None
        self.active_workspace = workspace
        self.save()
        self.workspace_changed.emit(old, workspace) # old, new

    def drop(self):
        if self.active_workspace:
            self.active_workspace.deactivate()

class Workspace(z.Entity):
    def __init__(self, id, name, items):
        self.name = name
        self.items = items
        super().__init__('workspace', id)
        self.label = self.name

        self.view = z.WorkspaceView
        self.preview = z.WorkspacePreview
        self.color = (0.2, 0.0, 0.7, 1)

    def activate(self):
        if 'floaties' not in self.items:
            self.items['floaties'] = []
        for floatie_data in self.items['floaties']:
            if 'launcher_code_entity_id' in floatie_data:
                entity = world.apps['Entities'].get_entity(floatie_data['launcher_code_entity_id'])
                floatie = world.floaties.add(code_entity=entity)
            else:
                entity = world.apps['Entities'].get_entity(floatie_data['class_entity_id'])
                print('workspace: adding class entity as floatie:', entity.name)
                cls = entity.eval()
                floatie = world.floaties.add(cls())
            floatie.layout.position = np.array(floatie_data['position'])
        world.floaties.changed.connect(self.floaties_changed)
        if 'kernels' not in self.items:
            self.items['kernels'] = []
        print(self.items['kernels'])
        for kernel_data in self.items['kernels']:
            kernel = world.kernels[kernel_data['id']]
            kernel.start_kernel()
        world.kernels.changed.connect(self.kernels_changed)

    def deactivate(self):
        world.floaties.changed.disconnect(self.floaties_changed)
        world.floaties.drop_all()
        world.kernels.changed.disconnect(self.kernels_changed)
        for id, kernel in world.kernels.kernels.items():
            if id != 0:
                kernel.stop_kernel()
                kernel.wait_for_kernel_stopped()

    def floaties_changed(self):
        self.items['floaties'] = []
        for floatie in world.floaties.floaties.values():
            if floatie.code_entity:
                self.items['floaties'].append({
                    'launcher_code_entity_id': floatie.code_entity.id,
                    'position': floatie.layout.position.tolist()
                })
                continue
            cls = floatie.obj.__class__
            if util.has_mandatory_params(cls.__init__):
                warning = f'WARNING: {cls.__name__} not added to workspace'
                print(warning)
                world.apps['Hud'].snackbar_host.show_message(warning)
                continue
            class_entity = z.ClassEntity.find(cls.__name__)
            self.items['floaties'].append({
                'class_entity_id': class_entity.id,
                'position': floatie.layout.position.tolist()
            })
        self.save()

    def kernels_changed(self):
        self.items['kernels'] = []
        for id, kernel in world.kernels.kernels.items():
            if id == 0:
                continue
            if kernel.status == 'started':
                self.items['kernels'].append({
                    'id': id
                })
        self.save()

    @classmethod
    def create(cls, name='', items=None):
        items = items or {}
        data = {'name': name, 'items': items}
        id = super().create('workspace', data)
        return cls(id, name, items)

    @classmethod
    def load(cls, id, data):
        return cls(id, data['name'], data.get('items', {}))

    @classmethod
    def find(cls, name):
        workspaces = world.apps['Entities'].get_entities('workspace')
        matches = [x for x in workspaces if x.name == name]
        if matches:
            return matches[0]
        raise Exception(f'Workspace "{name}" not found.')

    def dump_data(self):
        return {'name': self.name, 'items': self.items}

    def clone(self):
        return Workspace.create(name=self.name, items=self.items)

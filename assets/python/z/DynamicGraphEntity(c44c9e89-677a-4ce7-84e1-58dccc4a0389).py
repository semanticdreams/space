class DynamicGraphEntity(z.Entity):
    def __init__(self, id, positions, force_layout_params):
        self.positions = positions
        self.force_layout_params = force_layout_params
        super().__init__('dynamic-graph', id)

        self.view = None
        self.preview = None

    @classmethod
    def create(cls):
        positions = {}
        force_layout_params = {}
        id = super().create('dynamic-graph', data=dict(
            force_layout_params=force_layout_params, positions=positions))
        return cls(id, positions, force_layout_params)

    @classmethod
    def load(cls, id, data):
        data['positions'] = {str(k): v for k, v in data.get('positions', {}).items()}
        return cls(id, data['positions'], data.get('force_layout_params', {}))

    def dump_data(self):
        return {
            'positions': self.positions,
            'force_layout_params': self.force_layout_params,
        }

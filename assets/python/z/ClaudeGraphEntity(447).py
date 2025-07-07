class ClaudeGraphEntity(z.CompositeEntity):
    def __init__(self, components):
        super().__init__('claude-graph', components)

        self.view = z.ClaudeGraphEntityView
        self.preview = z.ClaudeGraphEntityPreview

    @classmethod
    def create(cls):
        graph_entity = z.GraphEntity.create()
        title_entity = z.StringEntity.create()
        return cls([graph_entity, title_entity])

    @classmethod
    def load(cls, id):
        pass

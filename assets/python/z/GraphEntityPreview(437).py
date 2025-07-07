class GraphEntityPreview:
    def __init__(self, entity, focus_parent=None):
        self.entity = entity
        assert isinstance(self.entity.id, str)
        node_count = len(self.entity.nodes)
        edge_count = len(self.entity.edges)
        self.button = z.ContextButton(
            label=f'graph: {node_count} nodes, {edge_count} edges',
            focus_parent=focus_parent,
            font_scale=5,
            actions=[
                ('view', lambda: world.floaties.add(
                    self.entity.view(self.entity))),
            ]
        )
        self.layout = self.button.layout

    def drop(self):
        self.button.drop()


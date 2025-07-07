class GraphEntityNodeNode(z.DynamicGraphNode):
    def __init__(self, graph_entity, entity):
        self.graph_entity = graph_entity
        self.entity = entity
        super().__init__(key=f'entity:{entity.id}', label=self.make_label(),
                         color=(0.2, 0.2, 1, 1),
                         sub_color=self.entity.color,
                         view=z.GraphEntityNodeNodeView
                        )
        self.entity.changed.connect(self.on_changed)

    def create_child(self):
        child_entity = self.entity.create()
        self.graph_entity.add_node(
            child_entity
        )
        self.graph_entity.add_edge(
            self.entity, child_entity)
        self.graph_entity.save()

    def remove_child(self):
        self.graph_entity.remove_node(self.entity.id)
        self.graph_entity.save()

    def make_label(self):
        return str(self.entity) if self.entity.label is None else self.entity.label

    def on_changed(self):
        self.label = self.make_label()
        self.set_sub_color(self.entity.color)
        self.changed.emit()

    def drop(self):
        self.entity.changed.disconnect(self.on_changed)
        super().drop()


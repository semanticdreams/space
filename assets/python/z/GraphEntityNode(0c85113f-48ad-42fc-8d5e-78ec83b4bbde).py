class GraphEntityNode(z.DynamicGraphNode):
    def __init__(self, entity):
        super().__init__(
            key = f'entity:{entity.id}',
            label='graph-entity',
            color=(1, 0.4, 1, 1),
            sub_color=(1, 0.4, 1, 1),
            view=z.GraphEntityNodeView,
        )
        self.entity = entity

        self.entity.changed.connect(self.update_graph)

        self.entity_node_map = {}

    def show_all(self):
        for node_id in self.entity.nodes:
            try:
                entity = world.apps['Entities'].get_entity(node_id)
            except z.EntityNotFoundError:
                self.entity.remove_node(node_id)
            else:
                if entity.id not in self.entity_node_map:
                    node = z.GraphEntityNodeNode(self.entity, entity)
                    self.entity_node_map[entity.id] = node
                    self.dynamic_graph.add_node(node,
                                                update_force_layout=False)
        self.entity.save(emit_changed=False)
        for edge in self.entity.edges:
            source_entity = world.apps['Entities'].get_entity(edge['source_id'])
            target_entity = world.apps['Entities'].get_entity(edge['target_id'])
            if source_entity and target_entity:
                self.dynamic_graph.add_edge(z.DynamicGraphEdge(
                    source=self.entity_node_map[source_entity.id],
                    target=self.entity_node_map[target_entity.id],
                    label=edge['label']
                ), update_force_layout=False)

        self.dynamic_graph.update_force_layout()

    def hide_all(self):
        for node in self.entity_node_map.values():
            self.dynamic_graph.remove_node(node, update_force_layout=False,
                                           clear_broken_edges=False)
        self.entity_node_map.clear()
        self.dynamic_graph.clear_broken_edges()
        self.dynamic_graph.update_force_layout()

    def update_graph(self):
        self.hide_all()
        self.show_all()

    def drop(self):
        self.entity.changed.disconnect(self.update_graph)

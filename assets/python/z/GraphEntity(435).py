class GraphEntity(z.Entity):
    def __init__(self, id, nodes, edges, positions, force_layout_params):
        self.nodes = nodes  # list of entity_ids
        self.edges = edges  # list of dicts: {'source_id', 'target_id', 'label', 'meta_id'}
        self.positions = positions
        self.force_layout_params = force_layout_params
        super().__init__('graph', id)

        self.view = z.GraphEntityView
        self.preview = z.GraphEntityPreview

    @classmethod
    def create(cls):
        id = super().create('graph')
        return cls(id, [], [], {}, {})

    @classmethod
    def load(cls, id, data):
        data['nodes'] = [str(x) for x in data['nodes']]
        data['edges'] = [{
            'source_id': str(x['source_id']),
            'target_id': str(x['target_id']),
            'meta_id': str(x['meta_id']),
            'label': x['label'],
        } for x in data['edges']]
        data['positions'] = {str(k): v for k, v in data.get('positions', {}).items()}
        return cls(id, data['nodes'], data['edges'],
                   data['positions'], data.get('force_layout_params', {}))

    def dump_data(self):
        return {
            'nodes': self.nodes,
            'edges': self.edges,
            'positions': self.positions,
            'force_layout_params': self.force_layout_params,
        }

    def add_node(self, entity, position=(0, 0, 0)):
        if entity.id not in self.nodes:
            self.nodes.append(entity.id)
            self.positions[entity.id] = position

    def remove_node(self, entity_id):
        node_id = entity_id
        self.positions.pop(entity_id, None)
        self.nodes = [n for n in self.nodes if n != node_id]
        self.edges = [e for e in self.edges if e['source_id'] != node_id and e['target_id'] != node_id]

    def has_node(self, entity):
        return entity.id in self.nodes

    def add_edge(self, source_entity, target_entity, label=None, meta_entity=None):
        source_id = source_entity.id
        target_id = target_entity.id
        if source_id not in self.nodes:
            self.nodes.append(source_id)
        if target_id not in self.nodes:
            self.nodes.append(target_id)

        self.edges.append({
            'source_id': source_id,
            'target_id': target_id,
            'label': label,
            'meta_id': meta_entity.id if meta_entity else None
        })

    def remove_edge(self, source_entity, target_entity):
        source_id = source_entity.id
        target_id = target_entity.id
        self.edges = [e for e in self.edges if not (e['source_id'] == source_id and e['target_id'] == target_id)]

    def has_edge(self, source_entity, target_entity):
        source_id = source_entity.id
        target_id = target_entity.id
        return any(e for e in self.edges if e['source_id'] == source_id and e['target_id'] == target_id)

    def get_neighbors(self, entity):
        entity_id = entity.id
        return list(set(
            [e['target_id'] for e in self.edges if e['source_id'] == entity_id] +
            [e['source_id'] for e in self.edges if e['target_id'] == entity_id]
        ))

    def get_outgoing(self, entity):
        entity_id = entity.id
        return [e for e in self.edges if e['source_id'] == entity_id]

    def get_incoming(self, entity):
        entity_id = entity.id
        return [e for e in self.edges if e['target_id'] == entity_id]

    def get_edge(self, source_entity, target_entity):
        source_id = source_entity.id
        target_id = target_entity.id
        for e in self.edges:
            if e['source_id'] == source_id and e['target_id'] == target_id:
                return e
        return None

    def update_edge_meta(self, source_entity, target_entity, new_meta_entity):
        edge = self.get_edge(source_entity, target_entity)
        if edge:
            edge['meta_id'] = new_meta_entity.id if new_meta_entity else None

    def clone(self):
        new_graph = GraphEntity.create()
        new_graph.nodes = list(self.nodes)
        new_graph.positions = dict(self.positions)
        new_graph.force_layout_params = self.force_layout_params.copy()
        new_graph.edges = [
            {
                'source_id': edge['source_id'],
                'target_id': edge['target_id'],
                'label': edge['label'],
                'meta_id': edge['meta_id']
            }
            for edge in self.edges
        ]
        return new_graph

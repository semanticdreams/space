class GraphEntityView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity
        assert isinstance(self.entity.id, str)

        #self.profiler = z.Profiler('graph-entity-view')

        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.entity.copy),
            ('paste entity as node', self.paste_triggered),
            ('show graph', self.show_graph_triggered),
            ('hide graph', self.hide_graph_triggered),
            ('create entity', self.create_entity_triggered),
        ], focus_parent=self.focus)

        self.link_source_entity = None
        self.link_target_entity = None
        self.link_label = z.Label('Link: ')
        self.link_source_button = z.Button('<paste source>', focus_parent=self.focus)
        self.link_source_button.clicked.connect(self.on_link_source_clicked)
        self.link_target_button = z.Button('<paste target>', focus_parent=self.focus)
        self.link_target_button.clicked.connect(self.on_link_target_clicked)
        self.link_submit_button = z.Button('submit', focus_parent=self.focus)
        self.link_submit_button.clicked.connect(self.on_link_submit_clicked)
        self.unlink_button = z.Button('unlink', focus_parent=self.focus)
        self.unlink_button.clicked.connect(self.on_unlink_clicked)
        self.link_row = z.Flex([
            z.FlexChild(self.link_label.layout),
            z.FlexChild(self.link_source_button.layout),
            z.FlexChild(self.link_target_button.layout),
            z.FlexChild(self.link_submit_button.layout),
            z.FlexChild(self.unlink_button.layout),
        ])

        self.force_layout = z.ForceLayout(
            spring_rest_length=self.entity.force_layout_params.get('spring_rest_length', 50),
            repulsive_force_constant=self.entity.force_layout_params.get('repulsive_force_constant', 6250),
            spring_constant=self.entity.force_layout_params.get('spring_constant', 1),
            max_displacement_squared=self.entity.force_layout_params.get('max_displacement_squared', 100),
            center_force=self.entity.force_layout_params.get('center_force', 0.0001),
            stabilized_max_displacement=self.entity.force_layout_params.get('stabilized_max_displacement', 0.02),
            stabilized_avg_displacement=self.entity.force_layout_params.get('stabilized_avg_displacement', 0.01),
        )
        self.force_layout.stabilized.connect(self.on_force_layout_stabilized)

        self.force_layout_view = z.ForceLayoutView(self.force_layout)
        self.force_layout_view.params_changed.connect(
            self.save_force_layout_params)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.link_row.layout),
            z.FlexChild(self.force_layout_view.layout),
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

        self.layout_root = z.LayoutRoot()

        self.graph_layout = z.Layout(
            measurer=self.graph_measurer,
            layouter=self.graph_layouter,
            uses_child_measures=True,
            name=f'graph-entity-{self.entity.id}'
        )
        self.graph_layout.set_root(self.layout_root)
        self.graph_layout.position = np.array((0, 300, 0), float)
        self.graph_layout.mark_measure_dirty()

        self.node_objs = {}
        self.points = {}
        self.edge_lines = {}

        self.update_graph()

        world.camera.debounced_camera_position.changed.connect(self.debounced_camera_position_changed)
        world.updated.connect(self.update)

    def __str__(self):
        return str(self.entity)

    def paste_triggered(self):
        assert Y.register_type == 'entity', Y.register_type
        entity = Y.value
        self.entity.add_node(entity)
        self.entity.save()
        self.update_graph()

    def create_entity_triggered(self):
        def on_submitted(item):
            entity = item[0].create()
            self.entity.add_node(entity)
            self.entity.save()
            self.update_graph()
        world.floaties.add(z.CreateEntityView(on_submitted=on_submitted))

    def show_graph_triggered(self):
        self.update_graph()

    def hide_graph_triggered(self):
        self.clear_graph()

    def on_link_source_clicked(self, f, i, d):
        assert Y.register_type == 'entity', Y.register_type
        self.link_source_entity = Y.value
        self.link_source_button.set_text(f'source: {self.link_source_entity}')

    def on_link_target_clicked(self, f, i, d):
        assert Y.register_type == 'entity', Y.register_type
        self.link_target_entity = Y.value
        self.link_target_button.set_text(f'target: {self.link_target_entity}')

    def on_link_submit_clicked(self, f, i, d):
        assert self.link_source_entity and self.link_target_entity
        self.entity.add_edge(self.link_source_entity, self.link_target_entity)
        self.entity.save()
        self.update_graph()

    def on_unlink_clicked(self, f, i, d):
        assert self.link_source_entity and self.link_target_entity
        self.entity.remove_edge(self.link_source_entity, self.link_target_entity)
        self.entity.save()
        self.update_graph()

    def debounced_camera_position_changed(self):
        for obj in self.node_objs.values():
            distance = np.linalg.norm(obj.layout.position - world.camera.debounced_camera_position.position)
            if distance < 500:
                obj.switch_view_mode('preview')
            else:
                obj.switch_view_mode('point')

    def update_graph(self):
        self.clear_graph()
        for node_id in self.entity.nodes:
            assert isinstance(node_id, str)
            try:
                entity = world.apps['Entities'].get_entity(node_id)
            except z.EntityNotFoundError:
                self.entity.remove_node(node_id)
                self.entity.save()
            assert isinstance(entity.id, str)
            if entity:
                self.add_node_obj(entity)
        for edge in self.entity.edges:
            source_entity = world.apps['Entities'].get_entity(edge['source_id'])
            target_entity = world.apps['Entities'].get_entity(edge['target_id'])
            if source_entity and target_entity:
                self.add_edge_line(source_entity, target_entity, edge['label'])
        self.update_force_layout()

    def add_node_obj(self, entity):
        if entity.id in self.node_objs:
            return
        obj = z.GraphEntityViewChild(self, entity, focus_parent=self.focus)
        self.node_objs[entity.id] = obj
        self.graph_layout.add_child(obj.layout)
        world.apps['Spatiolation'].add_spatiolatable(obj, on_moved=lambda drag: self.on_obj_moved())
        #obj.layout.position = np.random.rand(3) * 10
        #obj.layout.mark_measure_dirty()
        self.graph_layout.mark_measure_dirty()

    def remove_node(self, entity_id):
        self.entity.remove_node(entity_id)
        self.entity.save()
        self.update_graph()

    def add_edge_line(self, source_entity, target_entity, label=None):
        edge_key = (source_entity.id, target_entity.id)
        if source_entity.id not in self.node_objs or target_entity.id not in self.node_objs:
            return
        source_obj = self.node_objs[source_entity.id]
        target_obj = self.node_objs[target_entity.id]
        line = z.TriangleLine(
            source_obj.layout.position + source_obj.layout.size / 2,
            target_obj.layout.position + target_obj.layout.size / 2
        )
        self.edge_lines[edge_key] = line
        line.update()

    def update_edge_lines(self):
        for line in self.edge_lines.values():
            line.drop()
        self.edge_lines.clear()
        for edge in self.entity.edges:
            source_entity = world.apps['Entities'].get_entity(edge['source_id'])
            target_entity = world.apps['Entities'].get_entity(edge['target_id'])
            if source_entity and target_entity:
                self.add_edge_line(source_entity, target_entity, edge['label'])

    def update_force_layout(self, run_force=True):
        self.force_layout.clear()
        indices = {}
        for i, (node_id, node_obj) in enumerate(self.node_objs.items()):
            self.force_layout.add_node(node_obj.layout.position)
            indices[node_obj] = i
        for edge in self.entity.edges:
            if edge['source_id'] in self.node_objs and edge['target_id'] in self.node_objs:
                source_obj = self.node_objs[edge['source_id']]
                target_obj = self.node_objs[edge['target_id']]
                self.force_layout.add_edge(indices[source_obj], indices[target_obj])
        self.force_layout.position = self.graph_layout.position.copy()
        if run_force and self.node_objs:
            self.last_force_layout_position_update = time.time()
            self.force_layout.start()

    def save_force_layout_params(self):
        self.entity.force_layout_params = {
            'repulsive_force_constant': self.force_layout.repulsive_force_constant,
            'spring_rest_length': self.force_layout.spring_rest_length,
            'spring_constant': self.force_layout.spring_constant,
            'max_displacement_squared': self.force_layout.max_displacement_squared,
            'center_force': self.force_layout.center_force,
            'stabilized_max_displacement': self.force_layout.stabilized_max_displacement,
            'stabilized_avg_displacement': self.force_layout.stabilized_avg_displacement,
        }
        self.entity.save()

    def save_positions(self):
        for entity_id, node_obj in self.node_objs.items():
            self.entity.positions[entity_id] = node_obj.layout.position.tolist()
        self.entity.save()

    def on_obj_moved(self):
        for i, (entity_id, node_obj) in enumerate(self.node_objs.items()):
            self.force_layout.positions[i][:2] = node_obj.layout.position[:2]
        self.save_positions()

    def on_force_layout_stabilized(self):
        self.update_force_layout_positions()
        self.save_positions()

    def clear_graph(self):
        self.graph_layout.clear_children()
        for node_obj in self.node_objs.values():
            world.apps['Spatiolation'].remove_spatiolatable(node_obj)
            node_obj.drop()
        self.node_objs.clear()
        for line in self.edge_lines.values():
            line.drop()
        self.edge_lines.clear()

    def graph_measurer(self):
        for child in self.graph_layout.children:
            child.measurer()

    def graph_layouter(self):
        for child in self.graph_layout.children:
            child.size = child.measure
            if not np.any(child.position):
                child.position = np.array((0, 0, 0), float)
            child.rotation = np.array((1, 0, 0, 0), float)
            child.layouter()
        self.update_edge_lines()

    def update_force_layout_positions(self):
        self.last_force_layout_position_update = time.time()
        for i, obj in enumerate(self.node_objs.values()):
            obj.layout.position[:2] = self.force_layout.positions[i][:2]
        self.graph_layout.mark_layout_dirty()

    def update(self, delta):
        #self.profiler.enable()
        self.force_layout.update()
        if self.force_layout.active \
           and time.time() - self.last_force_layout_position_update > 0.3:
            self.update_force_layout_positions()
        self.layout_root.update()
        for edge_key, line in self.edge_lines.items():
            source_id, target_id = edge_key
            if source_id in self.node_objs and target_id in self.node_objs:
                source_obj = self.node_objs[source_id]
                target_obj = self.node_objs[target_id]
                line.start_position = source_obj.layout.position + source_obj.layout.size / 2
                line.end_position = target_obj.layout.position + target_obj.layout.size / 2
                line.update()
        #self.profiler.disable()

    def drop(self):
        #self.profiler.dump()
        #self.profiler.svg()
        world.camera.debounced_camera_position.changed.disconnect(self.debounced_camera_position_changed)
        world.updated.disconnect(self.update)
        self.force_layout_view.params_changed.disconnect(
            self.save_force_layout_params)
        self.force_layout.drop()
        self.clear_graph()
        self.graph_layout.drop()
        self.layout_root.drop()
        self.column.drop()
        self.force_layout_view.drop()
        self.link_row.drop()
        self.link_label.drop()
        self.link_source_button.drop()
        self.link_target_button.drop()
        self.link_submit_button.drop()
        self.unlink_button.drop()
        self.actions_panel.drop()
        self.focus.drop()

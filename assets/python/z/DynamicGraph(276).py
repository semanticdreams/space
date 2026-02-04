from collections import defaultdict


class DynamicGraph:
    def __init__(self, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = world.apps['Entities'].get_entity(
            '4c04f274-c318-4e01-935f-a00a2d57c65f'
        )

        self.points = {}
        self.labels = {}
        self.lines = {}

        self.node_view_objs = {}

        self.lod = {}

        self.selected_nodes = []
        self.selected_nodes_changed = z.Signal()

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
            z.FlexChild(self.force_layout_view.layout),
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

        world.camera.debounced_camera_position.changed.connect(self.debounced_camera_position_changed)

        world.apps['ObjectSelector'].changed.connect(self.on_selection_changed)

        world.updated.connect(self.update)

        self.add_node(z.StartNode(), pinned=True)

        world.vim.add_mode(z.DynamicGraphVimMode())
        world.vim.modes['leader'].add_action_group(z.VimActionGroup('dynamic-graph', [
            z.VimAction('dynamic-graph', self.set_current_mode_graph, sdl2.SDLK_g),
        ]))

    def set_current_mode_graph(self):
        world.vim.set_current_mode('dynamic-graph')

    def update_labels(self, nodes=None):
        if nodes is None:
            nodes = self.points.keys()
        for node in nodes:
            point = self.points[node]
            distance = np.linalg.norm(
                point.layout.position - world.camera.debounced_camera_position.position)
            current_lod = self.lod.get(node)
            if distance < 250:
                target_lod = 0
            elif distance < 500:
                target_lod = 1
            elif distance < 800:
                target_lod = 2
            else:
                target_lod = 3
            if current_lod != target_lod:
                if target_lod < 3:
                    if target_lod == 0:
                        text_length, line_length, text_scale = 120, 30, 3
                    elif target_lod == 1:
                        text_length, line_length, text_scale = 60, 20, 5
                    else:
                        text_length, line_length, text_scale = 20, None, 8
                    text = util.truncate_string_with_ellipsis(node.label, text_length)
                    if line_length:
                        text = util.wrap_text2(text, line_length)
                    if current_lod is None or current_lod >= 3:
                        span = z.Text(text, style=z.TextStyle(
                            scale=text_scale, color=(0.6, 0.6, 0.6, 1)))
                        self.labels[node] = span
                    else:
                        span = self.labels[node]
                        span.set_text(text)
                        span.style.scale = text_scale
                    span.layout.measurer()
                    offset = np.array((
                        -span.layout.measure[0]/2 + point.layout.size[0]/2,
                         -span.layout.measure[1],
                         0.05
                    ))
                    span.layout.position = point.layout.position + offset
                    span.layout.rotation = point.layout.rotation.copy()
                    span.layout.layouter()
                else:
                    if current_lod is not None:
                        self.labels.pop(node).drop()
                self.lod[node] = target_lod

    def debounced_camera_position_changed(self):
        self.update_labels()

    def on_selection_changed(self):
        self.selected_nodes = [node for node, point in self.points.items()
                               if point in world.apps['ObjectSelector'].selected]
        self.selected_nodes_changed.emit()

        self.update_node_views()

    def update_node_views(self):
        for node, view in list(self.node_view_objs.items()):
            if node not in self.selected_nodes:
                world.floaties.drop_obj(view)
                self.node_view_objs.pop(node)
        for node in self.selected_nodes:
            if node.view and node not in self.node_view_objs:
                obj = node.view(node)
                self.node_view_objs[node] = obj
                world.floaties.add(obj, side='right')

    def pin_node_view(self, obj):
        # removing node view obj from self.node_view_objs will
        # prevent its removal in update
        self.node_view_objs = {k: v for k, v in self.node_view_objs.items()
                               if v != obj}

    def add_node(self, node, update_force_layout=True, pinned=False):
        node.mount(self)
        point = z.Point(
            color=node.color, sub_color=node.sub_color, size=8, pinned=pinned,
            on_click=lambda f, i, d, node=node: self.node_clicked(node),
            on_double_click=lambda f, i, d, node=node: self.node_double_clicked(node),
        )
        point.layout.measurer()
        point.layout.size = point.layout.measure
        point.layout.position = np.array(
            self.entity.positions.get(node.key, (0, 0, 0)), float)
        point.layouter()
        self.points[node] = point
        world.apps['Spatiolation'].add_spatiolatable(point.layout, on_moved=lambda drag: self.on_obj_moved())
        world.apps['ObjectSelector'].add_selectables([point])
        if update_force_layout:
            self.update_force_layout()
        self.update_labels([node])

    def node_changed(self, node):
        if span := self.labels.get(node):
            self.update_labels([node])
        if point := self.points.get(node):
            point.set_sub_color(node.sub_color)

    def remove_node(self, node, update_force_layout=True, clear_broken_edges=True):
        node.unmount()
        node.drop()
        point = self.points.pop(node)
        world.apps['Spatiolation'].remove_spatiolatable(point.layout)
        world.apps['ObjectSelector'].remove_selectables([point])
        point.drop()
        if span := self.labels.pop(node, None):
            span.drop()
        if clear_broken_edges:
            self.clear_broken_edges()
        if update_force_layout:
            self.update_force_layout()

    def clear_broken_edges(self):
        for (source, target), line in list(self.lines.items()):
            if source not in self.points or target not in self.points:
                line.drop()
                del self.lines[(source, target)]

    def add_edge(self, edge, update_force_layout=True):
        if edge.source not in self.points:
            self.add_node(edge.source, update_force_layout=False)
        if edge.target not in self.points:
            self.add_node(edge.target, update_force_layout=False)
        source_layout = self.points[edge.source].layout
        target_layout = self.points[edge.target].layout
        if not np.any(target_layout.position):
            target_layout.position = source_layout.position * 1.2
        line = z.TriangleLine(
            source_layout.position + source_layout.size/2,
            target_layout.position + target_layout.size/2,
            color=edge.color,
        )
        line.update()
        self.lines[(edge.source, edge.target)] = line
        if update_force_layout:
            self.update_force_layout()

    def node_clicked(self, node):
        if point := self.points.get(node):
            world.apps['ObjectSelector'].set_selected([point])

    def node_double_clicked(self, node):
        for edge in node.get_edges():
            self.add_edge(edge)

    def update(self, delta):
        self.force_layout.update()
        if self.force_layout.active \
           and time.time() - self.last_force_layout_position_update > 0.3:
            self.update_force_layout_positions()
        positions_changed = False
        for node, point in self.points.items():
            if point.layout.layout_dirty:
                point.layout.layouter()
                point.layout.layout_dirty = False
                if span := self.labels.get(node):
                    span.layout.position = point.layout.position + np.array((-span.layout.measure[0]/2 + point.layout.size[0]/2, -span.layout.measure[1], 0.05))
                    span.layout.layouter()
                positions_changed = True
        if positions_changed:
            for (source, target), line in self.lines.items():
                source_layout = self.points[source].layout
                target_layout = self.points[target].layout
                line.set_start_position(source_layout.position + source_layout.size/2)
                line.set_end_position(target_layout.position + target_layout.size/2)
                line.update()

    def update_force_layout(self):
        self.force_layout.clear()
        self.indices = {}
        for i, point in enumerate(self.points.values()):
            self.force_layout.add_node(point.layout.position)
            self.indices[point] = i
            if point.pinned:
                self.force_layout.pin_node(i, True)
        for source, target in self.lines.keys():
            self.force_layout.add_edge(
                self.indices[self.points[source]],
                self.indices[self.points[target]],
            )
        if self.points:
            self.last_force_layout_position_update = time.time()
            self.force_layout.start()

    def update_force_layout_positions(self):
        self.last_force_layout_position_update = time.time()
        for point, i in self.indices.items():
            point.layout.set_position(np.array((*self.force_layout.positions[i], 0)))
        #self.shift_positions_to_center([0, 500, 0])

    def save_force_layout_params(self):
        self.force_layout.update_params()
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
        for node, point in self.points.items():
            self.entity.positions[node.key] = point.layout.position.tolist()
        self.entity.save()

    def shift_positions(self, offset):
        for point in self.points.values():
            point.layout.position += np.asarray(offset, float)
            self.force_layout.set_position(self.indices[point], point.layout.position)
        self.save_positions()

    def shift_positions_to_center(self, center):
        current_center = np.sum(np.array(
            [x.layout.position for x in self.points.values()]), axis=0) / len(self.points)
        self.shift_positions(np.asarray(center) - current_center)

    def on_obj_moved(self):
        for point in self.points.values():
            i = self.indices[point]
            self.force_layout.set_position(i, point.layout.position)
        self.save_positions()

    def on_force_layout_stabilized(self):
        self.update_force_layout_positions()
        self.save_positions()

    def drop_points(self):
        world.apps['ObjectSelector'].remove_selectables(self.points.values())
        for node, point in self.points.items():
            node.drop() # maybe use drop_nodes but need to move nodes to own list
            world.apps['Spatiolation'].remove_spatiolatable(point.layout)
            point.drop()
        self.points.clear()

    def drop_labels(self):
        for node, span in self.labels.items():
            span.drop()
        self.labels.clear()

    def drop_lines(self):
        for line in self.lines.values():
            line.drop()
        self.lines.clear()

    def drop(self):
        world.vim.modes['leader'].remove_action_group('dynamic-graph')
        world.vim.remove_mode('dynamic-graph')
        self.force_layout_view.params_changed.disconnect(
            self.save_force_layout_params)
        self.column.drop()
        self.force_layout_view.drop()
        world.camera.debounced_camera_position.changed.disconnect(self.debounced_camera_position_changed)
        world.updated.disconnect(self.update)
        self.force_layout.drop()
        self.drop_points()
        self.drop_labels()
        self.drop_lines()

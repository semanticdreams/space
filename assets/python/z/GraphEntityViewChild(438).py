class GraphEntityViewChild:
    def __init__(self, graph_entity_view, entity, focus_parent=None):
        self.focus = focus_parent.add_child(self)
        self.graph_entity_view = graph_entity_view
        self.entity = entity
        assert isinstance(self.entity.id, str)
        self.view_mode = 'point'
        self.dialog_actions = [
            ('icon:add', self.create_child_node),
            ('icon:remove', lambda: self.graph_entity_view.remove_node(self.entity.id)),
        ]
        self.point = z.Point(color=self.entity.color, size=8)
        self.layout = z.Layout(children=[self.point.layout], measurer=self.measurer,
                              layouter=self.layouter)
        self.dialog = None
        self.obj = None

        self.layout.position = np.array(self.graph_entity_view.entity.positions.get(self.entity.id, (0, 0, 0)), float)

        self.entity.changed.connect(self.on_entity_changed)

    def create_child_node(self):
        graph_entity = self.graph_entity_view.entity
        child_entity = self.entity.create()
        graph_entity.add_node(child_entity, position=(self.layout.position*1.2).tolist())
        graph_entity.add_edge(self.entity, child_entity)
        graph_entity.save()
        self.graph_entity_view.update_graph()

    def create_dialog(self):
        return z.Dialog(
            '{} ({})'.format(self.entity, self.graph_entity_view.entity), self.obj,
            actions=self.dialog_actions,
            color=self.entity.color
        )

    def measurer(self):
        self.layout.children[0].measurer()
        self.layout.measure = self.layout.children[0].measure

    def layouter(self):
        child = self.layout.children[0]
        child.position = self.layout.position
        child.rotation = self.layout.rotation
        child.size = self.layout.size
        child.layouter()

    def on_entity_changed(self):
        if self.view_mode == 'preview':
            self.switch_view_mode('point')
            self.switch_view_mode('preview')

    def switch_view_mode(self, view_mode):
        if view_mode == self.view_mode:
            return
        if view_mode == 'view':
            if self.point:
                self.point.drop()
                self.point = None
            self.obj = self.entity.view(self.entity, focus_parent=self.focus)
            if self.dialog:
                self.dialog.reset_child(self.obj)
            else:
                self.dialog = self.create_dialog()
                self.layout.set_children([self.dialog.layout])
        elif view_mode == 'preview':
            if self.point:
                self.point.drop()
                self.point = None
            self.obj = self.entity.preview(self.entity, focus_parent=self.focus)
            if self.dialog:
                self.dialog.reset_child(self.obj)
            else:
                self.dialog = self.create_dialog()
                self.layout.set_children([self.dialog.layout])
        else:
            self.dialog.drop()
            self.obj.drop()
            self.dialog = None
            self.obj = None
            self.point = z.Point(color=self.entity.color, size=8)
            self.layout.set_children([self.point.layout])
        self.layout.mark_measure_dirty()
        self.view_mode = view_mode

    def get_position(self):
        return self.layout.position

    def set_position(self, position):
        self.layout.position = position
        self.layout.mark_layout_dirty()
        self.graph_entity_view.update_edge_lines()

    def set_rotation(self, rotation):
        self.layout.rotation = rotation
        self.layout.mark_layout_dirty()

    def intersect(self, ray):
        return self.layout.intersect(ray)

    def drop(self):
        self.entity.changed.disconnect(self.on_entity_changed)
        if self.dialog:
            self.dialog.drop()
        if self.obj:
            self.obj.drop()
        if self.point:
            self.point.drop()
        self.focus.drop()

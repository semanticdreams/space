class GraphEntityNodeView:
    def __init__(self, node, focus_parent=world.focus):
        self.node = node
        self.focus = focus_parent.add_child(self)

        self.actions = [
            ('icon:keep', self.on_pin_triggered),
        ]

        self.actions_panel = z.ActionsPanel([
            ('show all', self.node.show_all),
            ('hide all', self.node.hide_all),
            ('copy entity', self.node.entity.copy),
            ('paste entity as node', self.paste_triggered),
            ('create entity', self.create_entity_triggered),
        ], focus_parent=self.focus)

        self.link_source_entity = None
        self.link_target_entity = None
        self.link_label = z.Label('Link: ')
        self.link_source_button = z.Button('<paste source>', focus_parent=self.focus)
        self.link_source_button.clicked.connect(self.on_link_source_clicked)
        self.link_swap_button = z.Button('icon:swap_horiz', focus_parent=self.focus)
        self.link_swap_button.clicked.connect(self.on_link_swap_clicked)
        self.link_target_button = z.Button('<paste target>', focus_parent=self.focus)
        self.link_target_button.clicked.connect(self.on_link_target_clicked)
        self.link_submit_button = z.Button('submit', focus_parent=self.focus)
        self.link_submit_button.clicked.connect(self.on_link_submit_clicked)
        self.unlink_button = z.Button('unlink', focus_parent=self.focus)
        self.unlink_button.clicked.connect(self.on_unlink_clicked)
        self.link_row = z.Flex([
            z.FlexChild(self.link_label.layout),
            z.FlexChild(self.link_source_button.layout),
            z.FlexChild(self.link_swap_button.layout),
            z.FlexChild(self.link_target_button.layout),
            z.FlexChild(self.link_submit_button.layout),
            z.FlexChild(self.unlink_button.layout),
        ], yalign='largest')

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.link_row.layout),
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

        self.node.dynamic_graph.selected_nodes_changed.connect(
            self.on_dynamic_graph_selected_nodes_changed)

    def on_dynamic_graph_selected_nodes_changed(self):
        selected_graph_entity_nodes = [
            x for x in self.node.dynamic_graph.selected_nodes
            if isinstance(x, z.GraphEntityNodeNode)
        ]
        if len(selected_graph_entity_nodes) == 2:
            source, target = selected_graph_entity_nodes
            self.set_source_entity(source.entity)
            self.set_target_entity(target.entity)

    def on_pin_triggered(self):
        self.node.dynamic_graph.pin_node_view(self)

    def paste_triggered(self):
        assert Y.register_type == 'entity', Y.register_type
        entity = Y.value
        self.node.entity.add_node(entity)
        self.node.entity.save()

    def create_entity_triggered(self):
        def on_submitted(item):
            entity = item[0].create()
            self.node.entity.add_node(entity)
            self.node.entity.save()
        world.floaties.add(z.CreateEntityView(on_submitted=on_submitted))

    def set_source_entity(self, entity):
        self.link_source_entity = entity
        self.link_source_button.set_text(f'source: {self.link_source_entity}')

    def set_target_entity(self, entity):
        self.link_target_entity = entity
        self.link_target_button.set_text(f'target: {self.link_target_entity}')

    def on_link_source_clicked(self, f, i, d):
        assert Y.register_type == 'entity', Y.register_type
        self.set_source_entity(Y.value)

    def on_link_target_clicked(self, f, i, d):
        assert Y.register_type == 'entity', Y.register_type
        self.set_target_entity(Y.value)

    def on_link_swap_clicked(self, f, i, d):
        tmp = self.link_source_entity
        self.set_source_entity(self.link_target_entity)
        self.set_target_entity(tmp)

    def on_link_submit_clicked(self, f, i, d):
        assert self.link_source_entity and self.link_target_entity
        self.node.entity.add_edge(self.link_source_entity, self.link_target_entity)
        self.node.entity.save()

    def on_unlink_clicked(self, f, i, d):
        assert self.link_source_entity and self.link_target_entity
        self.node.entity.remove_edge(self.link_source_entity, self.link_target_entity)
        self.node.entity.save()

    def drop(self):
        self.node.dynamic_graph.selected_nodes_changed.disconnect(
            self.on_dynamic_graph_selected_nodes_changed)
        self.column.drop()
        self.link_row.drop()
        self.link_label.drop()
        self.link_source_button.drop()
        self.link_swap_button.drop()
        self.link_target_button.drop()
        self.link_submit_button.drop()
        self.unlink_button.drop()
        self.actions_panel.drop()
        self.focus.drop()

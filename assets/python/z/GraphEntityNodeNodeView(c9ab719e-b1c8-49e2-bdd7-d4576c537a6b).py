class GraphEntityNodeNodeView:
    def __init__(self, node, focus_parent=world.focus):
        self.node = node
        self.focus = focus_parent.add_child(self)

        self.title = z.Button(str(self.node.entity), centered=False, wrap=False,
                              background_color=self.node.entity.color)

        self.copy_button = z.ContextButton(label='c', actions=[
            ('copy', self.node.entity.copy),
            ('copy id', lambda: Y(self.node.entity.id)),
            ('sys copy id', lambda: world.apps['Clipboard'].set_text(
                self.node.entity.id)),
        ])

        self.remove_child_button = z.ContextButton(label='-', actions=[
            ('remove-child', self.on_remove_child_triggered),
        ])

        self.create_child_button = z.ContextButton(label='+', actions=[
            ('create-child-same', self.on_create_child_triggered),
            ('create-child-different', self.on_create_different_child_triggered),

        ])

        self.meta_row = z.Flex([
            z.FlexChild(self.title.layout, flex=1),
            z.FlexChild(self.copy_button.layout),
            z.FlexChild(self.remove_child_button.layout),
            z.FlexChild(self.create_child_button.layout),
        ], yalign='largest')

        if self.node.entity.view:
            self.entity_view_obj = self.node.entity.view(self.node.entity)
        else:
            self.entity_view_obj = z.Label('entity has no view')

        self.column = z.Flex([
            z.FlexChild(self.meta_row.layout),
            z.FlexChild(self.entity_view_obj.layout),
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def on_remove_child_triggered(self):
        self.node.remove_child()

    def on_create_child_triggered(self):
        self.node.create_child()

    def on_create_different_child_triggered(self):
        def on_submitted(item):
            new_entity = item[0].create()
            self.node.graph_entity.add_node(new_entity)
            self.node.graph_entity.add_edge(
                self.node.entity, new_entity)
            self.node.graph_entity.save()
            world.floaties.drop_obj(create_entity_view)
        create_entity_view = z.CreateEntityView(
            on_submitted=on_submitted)
        world.floaties.add(create_entity_view)

    def drop(self):
        self.column.drop()
        self.meta_row.drop()
        self.title.drop()
        self.copy_button.drop()
        self.create_child_button.drop()
        self.remove_child_button.drop()
        self.entity_view_obj.drop()
        self.focus.drop()

class ClassesNodeView:
    def __init__(self, node, focus_parent=world.focus):
        self.node = node
        self.focus = focus_parent.add_child(self)
        self.search_view = z.SearchView(items=[], builder=self.search_view_item_builder,
                                        focus_parent=self.focus,
                                        num_per_page=5)
        self.layout = self.search_view.layout
        self.update_items()

    def search_view_item_builder(self, item, context):
        return z.ContextButton(
            label=item[1], focus_parent=context['focus_parent'],
            actions=[
                ('class', lambda: self.class_triggered(item[0])),
            ]
        )

    def class_triggered(self, cls):
        self.node.dynamic_graph.add_edge(z.DynamicGraphEdge(
            source=self.node,
            target=z.ClassNode(cls)
        ))

    def update_items(self):
        items = [(x, x['name']) for x in world.classes.codes.values()]
        self.search_view.set_items(items)

    def drop(self):
        self.search_view.drop()
        self.focus.drop()

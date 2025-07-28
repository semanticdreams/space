class StartNodeView:
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
                ('add', lambda: self.add_triggered(item[0])),
            ]
        )

    def add_triggered(self, node):
        self.node.dynamic_graph.add_edge(
            z.DynamicGraphEdge(source=self.node,
                               target=node))

    def update_items(self):
        nodes = [
            z.ClassesNode(),
            z.GraphEntityNode(world.apps['Entities'].get_entity('18')),
        ]
        items = [(x, x.key) for x in nodes]
        self.search_view.set_items(items)

    def drop(self):
        self.search_view.drop()
        self.focus.drop()

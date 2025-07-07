class GraphsView:
    def __init__(self):
        self.focus = world.focus.add_child(self)

        actions = [
            ('create graph', self.create_graph_triggered),
        ]
        self.head = z.ContextButton(label='graphs',
                                            color=(0.7, 0.3, 0.8, 1),
                                            focus_parent=self.focus,
                                            focusable=False,
                                            actions=actions)

        graphs = world.graphs.get_graphs()
        self.search_view = z.SearchView(
            [],
            builder=self.graph_item_builder,
            show_head=False,
            focus_parent=self.focus
        )

        self.column = z.Flex([self.head, self.search_view],
                                     axis='y')

        self.layout = self.column.layout
        self.spatiolator = z.Spatiolator(
            self.layout, self.head.spatiolator.handle)

        self.update_search_view_items()

    def graph_item_builder(self, item, context):
        return z.ContextButton(
            label=item[1],
            focus_parent=context['focus_parent'],
            color=(0.4, 0.9, 0.4, 1),
            actions=[
                ('view', lambda: self.view_triggered(item[0])),
                ('rename', lambda: self.rename_graph_triggered(item[0])),
                ('archive', lambda: self.archive_graph_triggered(item[0])),
            ]
        )

    def update_search_view_items(self):
        self.search_view.set_items(
            [(x, x['name']) for x in world.graphs.get_graphs()]
        )

    def view_triggered(self, graph):
        world.floaties.add(GraphView(model=GraphModel(graph)))

    def archive_graph_triggered(self, graph):
        world.graphs.archive_graph(graph['id'])
        self.update_search_view_items()

    def rename_graph_triggered(self, graph):
        new_name = world.dialogs.edit_string(graph['name']).strip()
        world.graphs.update_graph_name(graph['id'], new_name)
        self.update_search_view_items()

    def create_graph_triggered(self):
        graph = world.graphs.create_graph()
        self.update_search_view_items()

    def drop(self):
        self.column.drop()
        self.head.drop()
        self.search_view.drop()
        self.focus.drop()
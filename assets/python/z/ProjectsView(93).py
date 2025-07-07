class ProjectsView:
    def __init__(self):
        self.projects = world.classes.get_class(name='Projects')()

        self.name = z.ReactiveValue('projects')
        self.focus = world.focus.add_child(self)

        self.create_button = z.Button('+', focus_parent=self.focus)
        self.create_button.clicked.connect(self.create_clicked)

        self.reload_button = z.Button('reload', focus_parent=self.focus)
        self.reload_button.clicked.connect(self.reload_clicked)

        self.spacer = z.Spacer()

        self.head = z.Flex(
            children=[
                z.FlexChild(self.create_button.layout),
                z.FlexChild(self.reload_button.layout),
                z.FlexChild(self.spacer.layout, flex=1)
            ]
        )

        self.search_view = z.SearchView(items=[], builder=self.search_view_item_builder,
                                                focus_parent=self.focus, show_head=False)

        self.column = z.Flex([z.FlexChild(self.head.layout),
                                      z.FlexChild(self.search_view.layout)
                                      ], axis='y', xalign='largest')

        self.layout = self.column.layout

        self.update_items()

    def update_items(self):
        items = [(x, x['name'] or '') for x in self.projects.get_projects()]
        self.search_view.set_items(items)

    def reload_clicked(self, f, i, d):
        self.update_items()

    def drop(self):
        self.column.drop()
        self.search_view.drop()
        self.head.drop()
        self.spacer.drop()
        self.create_button.drop()
        self.reload_button.drop()
        self.focus.drop()

    def create_clicked(self, f, i, d):
        project = self.projects.create_project()
        self.update_items()
        world.floaties.add(world.classes.get_class(name='ProjectView')(project))

    def get_triggered(self, cls):
        world.floaties.add(world.classes.get_class(name='ProjectView')(cls))

    def search_view_item_builder(self, item, context):
        b = z.ContextButton(label=item[1], focus_parent=context['focus_parent'], color=(0.4, 0.9, 0.4, 1),
                   actions=[
                       ('get', lambda: self.get_triggered(item[0])),
                   ])
        return b
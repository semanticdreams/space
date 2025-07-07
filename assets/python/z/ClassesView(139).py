class ClassesView:
    def __init__(self):
        self.focus = world.focus.add_child(self)

        self.create_class_button = z.Button('+', focus_parent=self.focus)
        self.create_class_button.clicked.connect(self.create_class_clicked)

        self.reload_button = z.Button('reload', focus_parent=self.focus)
        self.reload_button.clicked.connect(self.reload_clicked)

        self.head = z.Flex(
            children=[
                z.FlexChild(self.create_class_button.layout),
                z.FlexChild(self.reload_button.layout),
            ]
        )

        self.search_view = z.SearchView(items=[], builder=self.search_view_item_builder,
                                                focus_parent=self.focus, show_head=False)

        self.column = z.Flex([
        z.FlexChild(self.head.layout), z.FlexChild(self.search_view.layout, flex=1)], axis='y', xalign='largest')

        self.layout = self.column.layout

        self.update_items()

        world.focus.set_focus(self.search_view.focus)

    def update_items(self):
        #items = [(x, x['name']) for x in world.classes.codes.values()]
        items = [(x, x.name) for x in z.ClassEntity.all()]
        self.search_view.set_items(items)

    def reload_clicked(self, f, i, d):
        self.update_items()

    def drop(self):
        self.column.drop()
        self.search_view.drop()
        self.head.drop()
        self.create_class_button.drop()
        self.reload_button.drop()
        self.focus.drop()

    def create_class_clicked(self, f, i, d):
        class_entity = z.ClassEntity.create()
        #class_code = world.classes.create_class_code(lang='py')
        self.update_items()
        #ClassView = world.classes.get_class(name='ClassView')
        #world.floaties.add(ClassView(class_code))
        world.floaties.add(
            code_entity=z.CodeEntity.create(
                code_str=f'z.ClassEntityView(z.Entity.get("{class_entity.id}"))'
            )
        )

    def get_triggered(self, cls):
        world.floaties.drop_obj(self)
        world.floaties.add(
            code_entity=z.CodeEntity.create(
                code_str=f'z.ClassEntityView(z.Entity.get("{cls.id}"))'
            )
        )

    def search_view_item_builder(self, item, context):
        b = z.ContextButton(label=item[1], focus_parent=context['focus_parent'], color=(0.4, 0.9, 0.4, 1),
                   actions=[
                       ('get', lambda: self.get_triggered(item[0])),
                   ])
        return b

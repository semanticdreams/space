class CodesView:
    def __init__(self):
        self.focus = world.focus.add_child(self)
        self.name = z.ReactiveValue('codes')
        actions = [
            ('create code', self.on_create_code_triggered),
            ('reload', self.update_items),
        ]
        self.buttons = []
        for name, func in actions:
            button = z.Button(name, focus_parent=self.focus)
            button.clicked.connect(lambda f, i, d, func=func: func())
            self.buttons.append(button)
        self.spacer = z.Spacer()
        self.head = z.Flex(children=[
            *[z.FlexChild(x.layout) for x in self.buttons],
            z.FlexChild(self.spacer.layout, flex=1)
        ])
        self.search_view = z.SearchView(
            builder=self.search_view_item_builder, items=[], focus_parent=self.focus, show_head=False)
        self.column = z.Flex([
            z.FlexChild(self.head.layout),
            z.FlexChild(self.search_view.layout)
        ], axis='y', xalign='largest')
        self.layout = self.column.layout

        self.update_items()

    def search_view_item_builder(self, item, context):
        CodeView = world.classes.get_class(name='CodeView')
        b = z.ContextButton(label=item[1], focus_parent=context['focus_parent'], color=(0.4, 0.9, 0.4, 1),
                   actions=[
                       ('get', lambda: world.floaties.add(CodeView(item[0]))),
                   ])
        return b

    def on_create_code_triggered(self):
        world.codes.create_code()
        self.update_items()

    def update_items(self):
        codes = world.codes.get_codes()
        items = [(x, x['name']) for x in codes]
        self.search_view.set_items(items)

    def drop(self):
        self.column.drop()
        self.head.drop()
        self.spacer.drop()
        self.search_view.drop()
        for button in self.buttons:
            button.drop()
        self.focus.drop()

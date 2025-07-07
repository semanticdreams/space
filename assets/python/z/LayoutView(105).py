class LayoutView:
    def __init__(self, lt):
        self.lt = lt

        self.focus = world.focus.add_child(self)
        self.name = z.ReactiveValue(self.make_name())

        actions = [
            ('reload', self.reload_triggered),
            ('stats', lambda: world.floaties.add(world.classes['LayoutStatsView'](self.lt))),
        ]
        self.action_buttons = []
        for name, func in actions:
            button = z.Button(name, focus_parent=self.focus)
            button.clicked.connect(lambda f, i, d, func=func: func())
            self.action_buttons.append(button)
        self.spacer = z.Spacer()
        self.head = z.Flex(children=[
            *[z.FlexChild(x) for x in self.action_buttons],
            z.FlexChild(self.spacer, flex=1)
        ])

        self.list_view = z.ListView(self.lt.children, show_head=False, focus_parent=self.focus, builder=self.builder)

        self.column = z.Flex([self.head, self.list_view], axis='y', xalign='largest')
        self.layout = self.column.layout

    def builder(self, item, context):
        return z.ContextButton(
            label=item.name, focus_parent=context['focus_parent'],
            actions=[
                ('get', lambda item=item: world.floaties.add(LayoutView(item))),
            ]
        )

    def reload_triggered(self):
        self.list_view.set_items(self.lt.children)

    def make_name(self):
        return f'Layout: {self.lt.name}'

    def drop(self):
        self.column.drop()
        self.head.drop()
        self.spacer.drop()
        for button in self.action_buttons:
            button.drop()
        self.list_view.drop()
        self.focus.drop()
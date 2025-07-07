class LaunchableCodesView:
    def __init__(self):
        self.name = z.ReactiveValue('launchable-codes')
        self.focus = world.focus.add_child(self)
        actions = [
            ('create launchable code', self.create_triggered),
            ('reload', self.load_launchable_codes),
        ]
        self.head = world.classes['ActionsPanel'](actions, self.focus)
        #self.buttons = []
        #for name, func in actions:
        #    button = Button(name, focus_parent=self.focus)
        #    button.clicked.connect(lambda f, i, d, func=func: func())
        #    self.buttons.append(button)
        #self.spacer = Spacer()
        #self.head = Flex(children=[
        #    *[FlexChild(x.layout) for x in self.buttons],
        #    FlexChild(self.spacer.layout, flex=1)
        #])
        self.search_view = z.SearchView(items=[], builder=self.builder,
                                      focus_parent=self.focus, show_head=False)
        self.column = z.Flex([
            z.FlexChild(self.head.layout),
            z.FlexChild(self.search_view.layout)], axis='y', xalign='largest')
        self.layout = self.column.layout

        self.load_launchable_codes()

    def load_launchable_codes(self):
        items = [(x, x['name'] or '') for x in world.apps['LaunchableCodes'].get_launchable_codes()]
        self.search_view.set_items(items)

    def builder(self, item, context):
        return z.ContextButton(label=item[1], focus_parent=context['focus_parent'], actions=[
            ('get', lambda item=item: self.get_launchable_code_triggered(item[0])),
            ('delete', lambda item=item: self.delete_launchable_code_triggered(item[0])),
        ])

    def create_triggered(self):
        code_id = world.codes.create_code()
        launchable_code = world.apps['LaunchableCodes'].create_launchable_code(code_id)
        self.load_launchable_codes()
        world.floaties.add(world.classes['LaunchableCodeView'](launchable_code))

    def get_launchable_code_triggered(self, item):
        world.floaties.add(world.classes['LaunchableCodeView'](item))

    def delete_launchable_code_triggered(self, item):
        world.apps['LaunchableCodes'].delete_launchable_code(item['name'])
        self.load_launchable_codes()

    def drop(self):
        self.column.drop()
        self.head.drop()
        #self.spacer.drop()
        #for button in self.buttons:
        #    button.drop()
        self.search_view.drop()
        self.focus.drop()
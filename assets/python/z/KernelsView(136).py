class KernelsView:
    def __init__(self):
        self.name = z.ReactiveValue('kernels')
        self.focus = world.focus.add_child(self)

        actions = [
            ('create', self.create_item),
            ('reload', self.load_items),
        ]
        self.actions_panel = z.ActionsPanel(actions, self.focus)
        #self.buttons = []
        #for name, func in actions:
        #    button = z.Button(name, focus_parent=self.focus)
        #    button.clicked.connect(lambda f,i,d, func=func: func())
        #    self.buttons.append(button)
        #self.spacer = z.Spacer()
        #self.head = z.Flex(children=[
        #    *[z.FlexChild(x) for x in self.buttons],
        #    z.FlexChild(self.spacer, flex=1)
        #])
        self.search_view = z.SearchView(items=[], builder=self.search_view_item_builder,
                                                focus_parent=self.focus, show_head=False)
        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.search_view.layout)
        ], axis='y', xalign='largest')
        self.layout = self.column.layout

        self.load_items()

    def search_view_item_builder(self, item, context):
        b = z.ContextButton(label=item[1], focus_parent=context['focus_parent'], color=(0.4, 0.9, 0.4, 1),
                   actions=[
                       ('get', lambda: world.floaties.add(world.classes['InternalKernelView' if item[0].id == 0 else 'SubprocessKernelView'](item[0]))),
                   ])
        return b

    def load_items(self):
        self.items = world.kernels.kernels.values()
        self.items_updated()

    def items_updated(self):
        self.search_view.set_items([(x, x.name or '') for x in self.items])

    def create_item(self):
        kernel = world.kernels.create_subprocess_kernel('', '', '')
        self.load_items()

    def drop(self):
        self.column.drop()
        self.search_view.drop()
        self.actions_panel.drop()
        #self.head.drop()
        #self.spacer.drop()
        #for button in self.buttons:
        #    button.drop()
class ClaudeView:
    def __init__(self):
        self.claude = world.apps['ClaudeApp'].claude
        self.name = z.ReactiveValue('claude')
        self.focus = world.focus.add_child(self)

        actions = [
            ('create conversation', self.create_conversation),
            ('reload', self.load_conversations),
        ]
        self.buttons = []
        for name, func in actions:
            button = z.Button(name, focus_parent=self.focus)
            button.clicked.connect(lambda f,i,d, func=func: func())
            self.buttons.append(button)
        self.spacer = z.Spacer()
        self.head = z.Flex(children=[
            *[z.FlexChild(x.layout) for x in self.buttons],
            z.FlexChild(self.spacer.layout, flex=1)
        ])
        self.search_view = z.SearchView(items=[], builder=self.search_view_item_builder,
                                                focus_parent=self.focus, show_head=False)
        self.column = z.Flex([
            z.FlexChild(self.head.layout),
            z.FlexChild(self.search_view.layout, flex=1)
        ], axis='y', xalign='largest')
        self.layout = self.column.layout

        self.load_conversations()

    def search_view_item_builder(self, item, context):
        b = z.ContextButton(label=item[1], focus_parent=context['focus_parent'], color=(0.4, 0.9, 0.4, 1),
                   actions=[
                       ('get', lambda: world.floaties.add(z.ClaudeConversationView(item[0]))),
                   ])
        return b

    def load_conversations(self):
        self.conversations = self.claude.get_conversations()
        self.conversations_updated()

    def create_conversation(self):
        conversation = self.claude.create_conversation()
        self.conversations.append(conversation)
        self.conversations_updated()
        world.floaties.add(z.ClaudeConversationView(conversation))

    def conversations_updated(self):
        self.search_view.set_items([(x, x.data['name'] or '') for x in self.conversations])

    def drop(self):
        self.column.drop()
        self.search_view.drop()
        self.head.drop()
        self.spacer.drop()
        for button in self.buttons:
            button.drop()
        self.focus.drop()

class ClaudeConversationView:
    def __init__(self, conversation):
        self.focus = world.focus.add_child(self)
        self.conversation = conversation
        self.name = z.ReactiveValue(self.make_name())
        self.messages = []

        self.name_input = z.Input(text=self.conversation.data['name'] or '', focus_parent=self.focus)
        self.name_input.submitted.connect(self.on_name_submitted)
        self.auto_name_button = z.Button('auto-name', focus_parent=self.focus,
                on_click=self.on_auto_name_clicked)
        self.archive_button = z.Button('archive', focus_parent=self.focus)
        self.archive_button.clicked.connect(self.on_archive_clicked)
        self.clone_button = z.Button('clone', focus_parent=self.focus)
        self.clone_button.clicked.connect(self.on_clone_clicked)
        self.temperature_input = z.Input(text=str(self.conversation.data['temperature']), focus_parent=self.focus)
        self.temperature_input.submitted.connect(self.on_temperature_submitted)
        self.max_tokens_input = z.Input(text=str(self.conversation.data['max_tokens']), focus_parent=self.focus)
        self.max_tokens_input.submitted.connect(self.on_max_tokens_submitted)
        self.head_spacer = z.Spacer()
        self.head = z.Flex(children=[
            z.FlexChild(self.name_input.layout),
            z.FlexChild(self.auto_name_button.layout),
            z.FlexChild(self.archive_button.layout),
            z.FlexChild(self.clone_button.layout),
            z.FlexChild(self.temperature_input.layout),
            z.FlexChild(self.max_tokens_input.layout),
            z.FlexChild(self.head_spacer.layout, flex=1),
        ], yalign='largest')

        self.system_input = z.Input(
            text=self.conversation.data['system'] or '',
            focus_parent=self.focus, multiline=True, min_lines=3, max_lines=3)
        self.system_input.submitted.connect(self.on_system_submitted)

        self.tab_view = z.TabView([
            ('Tabs', self.tab_builder),
            ('Text', self.text_builder),
            #('List', self.list_builder)
        ], focus_parent=self.focus, horizontal=True)

        self.input = z.Input(focus_parent=self.focus, max_lines=5, min_lines=5, multiline=True, actions=[
            ('paste', self.input_paste_triggered),
        ])
        self.input.submitted.connect(self.on_submitted)

        self.send_button = z.Button('send', focus_parent=self.focus)
        self.send_button.clicked.connect(self.on_send_clicked)

        self.bottom = z.Flex(children=[
            z.FlexChild(self.input.layout, flex=1),
            z.FlexChild(self.send_button.layout)
        ], yalign='largest')

        self.column = z.Flex([
            z.FlexChild(self.head.layout),
            z.FlexChild(self.system_input.layout),
            z.FlexChild(self.tab_view.layout, flex=1),
            z.FlexChild(self.bottom.layout)
        ], axis='y', xalign='largest')
        self.layout = self.column.layout

        self.load_messages()

        world.focus.set_focus(self.input.focus)

    def on_auto_name_clicked(self, f, i, d):
        def cb(value):
            self.name_input.set_text(value)
            self.conversation.data['name'] = value
            self.name.set(self.make_name())
        world.aio.create_task(self.conversation.auto_name(), cb)

    def tab_builder(self, context):
        def make_message_builder(message):
            def b(context2):
                inp = z.Input(text='\n'.join((message['content'], message['tool_uses'])) if message['tool_uses'] else (message['content'] or ''), multiline=True,
           # background_color=(0, 0.8, 0.8, 1) if message['role'] == 'assistant' else (0, 1.0, 0.5, 1),
                                       actions=[
                                           ('archive', lambda message=message: self.archive_message_triggered(message)),
                                           ('edit role', lambda message=message: self.edit_role_triggered(message)),
                                           ('xml', lambda message=message: self.xml_triggered(message)),
                                       ],
                                       chars_per_line=80,
                                       focus_parent=context2['focus_parent'])
                inp.submitted.connect(lambda: self.conversation.set_message_content(message['id'], inp.text))
                return inp
            return b
        tabs = [((('> ' if x['role'] == 'assistant' else '') \
                 + 'tool result' if x['type'] == 'tool_result' else x['content'].split('\n')[0])[:20], make_message_builder(x)) for x in self.messages]
        tab_view = z.TabView(tabs, focus_parent=context['focus_parent'],
                                     horizontal=False, initial_tab=-1)
        return tab_view

    def text_builder(self, context):
        format_reply = lambda s: '\n'.join(('> ' + x for x in s.split('\n')))
        text = '\n\n'.join([(x['content'] if x['role'] == 'user' else format_reply(x['content']))
                            for x in self.messages])
        return z.Input(text=text,
                               multiline=True,
                               min_width=80, chars_per_line=80,
                               focus_parent=context['focus_parent'])

    #def list_builder(self, context):
    #    list_view = z.ListView(self.messages, builder=self.builder, focus_parent=context['focus_parent'], show_head=False)
    #    return list_view

    def input_paste_triggered(self):
        prev_inserting = self.input.inserting
        self.input.set_inserting(True)
        for char in world.apps['Clipboard'].get_text():
            self.input.insert_char(char)
        self.input.set_inserting(prev_inserting)

    def make_name(self):
        return f'Claude Conversation {self.conversation.data["id"]}: {self.conversation.data["name"] or ""}'

    def edit_role_triggered(self, message):
        message['role'] = world.dialogs.edit_string(message['role']).strip()
        self.conversation.set_message_role(message['id'], message['role'])
        self.messages_updated()

    def xml_triggered(self, message):
        world.floaties.add(z.XMLView.from_text(message['content']))

    def on_system_submitted(self):
        value = self.system_input.text
        self.conversation.set_system(value)

    def on_temperature_submitted(self):
        value = float(self.temperature_input.text)
        self.conversation.set_temperature(value)

    def on_max_tokens_submitted(self):
        value = int(self.max_tokens_input.text)
        self.conversation.set_max_tokens(value)

    def on_name_submitted(self):
        new_name = self.name_input.text
        self.conversation.set_name(new_name)
        self.name.set(self.make_name())

    def on_archive_clicked(self, f, i, d):
        self.conversation.set_archived()
        world.floaties.drop_obj(self)

    def on_clone_clicked(self, f, i, d):
        conversation = self.conversation.clone()
        world.floaties.add(ClaudeConversationView(conversation))

    def archive_message_triggered(self, message):
        self.conversation.archive_message(message['id'])
        self.load_messages()

    def messages_updated(self):
        #self.list_view.set_items(self.messages)
        self.tab_view.reload_current_tab()

    def load_messages(self):
        self.messages = self.conversation.get_messages()
        self.messages_updated()
        self.send_button.set_text('send')

    def on_send_clicked(self, f, i, d):
        self.send_button.set_text('sending...')
        self.send_messages()

    def on_submitted(self):
        value = self.input.text.strip()
        if value:
            user_message = self.conversation.insert_message(value, 'user')
            self.load_messages()
        self.input.set_text('')

    def send_messages(self):
        world.aio.create_task(self.conversation.send(),
            lambda _: self.load_messages())

    def drop(self):
        self.column.drop()
        self.head.drop()
        self.name_input.drop()
        self.auto_name_button.drop()
        self.system_input.drop()
        self.temperature_input.drop()
        self.max_tokens_input.drop()
        self.archive_button.drop()
        self.clone_button.drop()
        self.head_spacer.drop()
        self.bottom.drop()
        self.input.drop()
        self.send_button.drop()
        self.tab_view.drop()
        self.focus.drop()

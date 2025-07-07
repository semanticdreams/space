class CodebookView:

    def __init__(self, codebook):
        self.codebook = codebook
        self.name = z.ReactiveValue(self.make_name())
        self.focus = world.focus.add_child(self)
        self.name_input = Input(text=self.codebook.data['name'] or '', focus_parent=self.focus)
        self.name_input.submitted.connect(self.name_submitted)
        self.default_kernel_input = Input(text=str(self.codebook.data['default_kernel']), focus_parent=self.focus)
        self.default_kernel_input.submitted.connect(self.default_kernel_submitted)
        self.code_id_input = Input(text='', focus_parent=self.focus)
        self.code_id_input.submitted.connect(self.code_id_submitted)
        actions = [('reload', self.load_codes), ('delete', self.delete_triggered), ('new code', self.new_code_triggered)]
        self.buttons = []
        for (name, func) in actions:
            button = Button(name, focus_parent=self.focus)
            button.clicked.connect(lambda f, i, d, func=func: func())
            self.buttons.append(button)
        self.spacer = Spacer()
        self.row = Flex(children=[FlexChild(self.name_input), FlexChild(self.default_kernel_input), FlexChild(self.code_id_input), *[FlexChild(x) for x in self.buttons], FlexChild(self.spacer, flex=1)])
        self.list_view = ListView([], focus_parent=self.focus, show_head=False, builder=self.item_builder)
        self.column = Flex(xalign='largest', axis='y', children=[FlexChild(self.row), FlexChild(self.list_view)])
        self.layout = self.column.layout
        self.codes = []
        self.errors = {}
        self.outputs = {}
        self.running_codes = set()
        self.done_codes = set()
        self.load_codes()

    def item_builder(self, item, context):
        if item[0] == 'code':
            code = item[1]
            return ContextButton(label=code['code'], focus_parent=context['focus_parent'], color=(0.8, 0.8, 1, 1) if code['id'] in self.running_codes else (0.9, 0.9, 0.4, 1) if code['id'] in self.done_codes else (1.0, 1.0, 0.8, 1), actions=[('run', lambda : self.run_code_triggered(code)), ('get', lambda : self.get_code_triggered(code)), ('move up', lambda : self.move_code_up_triggered(code)), ('move down', lambda : self.move_code_down_triggered(code)), ('edit', lambda : self.edit_code_triggered(code)), ('edit kernel', lambda : self.edit_code_kernel_triggered(code)), ('delete code', lambda : self.delete_code_triggered(code)), ('remove from codebook', lambda : self.remove_code_from_codebook_triggered(code))])
        elif item[0] == 'output':
            output = item[1]
            return ContextButton(label=output, focus_parent=context['focus_parent'], color=(0.6, 1.0, 0.6, 1), actions=[('edit', lambda : world.dialogs.edit_string(output))])
        elif item[0] == 'error':
            error = item[1]
            return ContextButton(label=error, focus_parent=context['focus_parent'], color=(1.0, 0.6, 0.6, 1), actions=[('edit', lambda : world.dialogs.edit_string(error))])

    def run_code_triggered(self, code):
        self.outputs.pop(code['id'], None)
        self.errors.pop(code['id'], None)
        self.done_codes.discard(code['id'])
        self.running_codes.add(code['id'])
        world.codes.run_code(code, catch_errors=True, registers=self.codebook.registers, callback=lambda result: self.on_code_callback(code, result))
        self.update_items()

    def on_code_callback(self, code, result):
        self.codebook.registers = result['registers']
        if (output := (result['output'] or '').strip()):
            self.outputs[code['id']] = output
        if (error := (result['error'] or '').strip()):
            self.errors[code['id']] = error
        else:
            self.done_codes.add(code['id'])
        self.running_codes.discard(code['id'])
        self.update_items()

    def get_code_triggered(self, code):
        world.floaties.add(z.CodeView(code))

    def move_code_up_triggered(self, code):
        self.codebook.move_code_up(code)
        self.load_codes()

    def move_code_down_triggered(self, code):
        self.codebook.move_code_down(code)
        self.load_codes()

    def edit_code_triggered(self, code):
        world.codes.edit_code(code)
        self.update_items()

    def edit_code_kernel_triggered(self, code):
        world.codes.edit_code_kernel(code)

    def delete_code_triggered(self, code):
        self.codebook.delete_code(code)
        self.outputs.pop(code['id'], None)
        self.errors.pop(code['id'], None)
        self.codes = [x for x in self.codes if x['id'] != code['id']]
        self.update_items()

    def remove_code_from_codebook_triggered(self, code):
        self.codebook.remove_code_from_codebook(code['id'])
        self.outputs.pop(code['id'], None)
        self.errors.pop(code['id'], None)
        self.codes = [x for x in self.codes if x['id'] != code['id']]
        self.update_items()

    def update_items(self):
        items = []
        for code in self.codes:
            items.append(('code', code))
            if (output := self.outputs.get(code['id'])):
                items.append(('output', output))
            if (error := self.errors.get(code['id'])):
                items.append(('error', error))
        self.list_view.set_items(items)

    def load_codes(self):
        self.codes = self.codebook.get_codebook_codes()
        self.update_items()

    def code_id_submitted(self):
        code_id = int(self.code_id_input.text)
        self.codebook.add_code(code_id)
        self.load_codes()

    def new_code_triggered(self):
        self.codebook.new_code()
        self.load_codes()

    def make_name(self):
        return f"codebook: {self.codebook.data['name']}"

    def delete_triggered(self):
        self.codebook.drop_codebook()
        world.floaties.drop_obj(self)

    def name_submitted(self):
        self.codebook.update_name(self.name_input.text.strip())
        self.name.set(self.make_name())

    def default_kernel_submitted(self):
        self.codebook.update_default_kernel(int(self.default_kernel_input.text.strip()))

    def drop(self):
        self.column.drop()
        self.row.drop()
        self.list_view.drop()
        self.name_input.drop()
        self.default_kernel_input.drop()
        self.code_id_input.drop()
        self.spacer.drop()
        for button in self.buttons:
            button.drop()
        self.focus.drop()

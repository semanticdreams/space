class LaunchableCodeView:
    def __init__(self, launchable_code):
        self.launchable_code = launchable_code
        self.name = z.ReactiveValue('launchable-code')
        self.focus = world.focus.add_child(self)
        self.name_input = z.Input(text=self.launchable_code['name'] or '', focus_parent=self.focus)
        self.code_id_input = z.Input(text=str(self.launchable_code['code_id']), focus_parent=self.focus)
        self.get_code_button = z.Button('get code', focus_parent=self.focus)
        self.get_code_button.clicked.connect(self.on_get_code_clicked)
        self.save_button = z.Button('save', focus_parent=self.focus)
        self.save_button.clicked.connect(self.on_save_clicked)
        self.row = z.Flex(children=[
            z.FlexChild(self.name_input.layout),
            z.FlexChild(self.code_id_input.layout),
            z.FlexChild(self.get_code_button.layout),
            z.FlexChild(self.save_button.layout),
        ])
        self.layout = self.row.layout

    def on_get_code_clicked(self, f, i, d):
        code_id = int(self.code_id_input.text)
        code = world.codes.get_code(code_id)
        CodeView = world.classes.get_class(name='CodeView')
        world.floaties.add(CodeView(code))

    def on_save_clicked(self, f, i, d):
        code_id = self.launchable_code['code_id']
        name = self.name_input.text
        world.codes.update_code_name(dict(id=code_id, name=f'launch-{name}'))
        world.apps['LaunchableCodes'].update_launchable_code(code_id, name)

    def drop(self):
        self.row.drop()
        self.name_input.drop()
        self.code_id_input.drop()
        self.get_code_button.drop()
        self.save_button.drop()
        self.focus.drop()
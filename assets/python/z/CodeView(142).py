import ast
class CodeView:
    def __init__(self, code):
        self.code = code
        self.focus = world.focus.add_child(self)
        actions = [
            ('edit', self.edit_triggered),
            ('ast', self.ast_triggered),
            ('run', self.run_triggered),
            ('archive', self.archive_triggered),
        ]
        self.name_input = z.Input(text=self.code['name'] or '', focus_parent=self.focus)
        self.name_input.submitted.connect(self.on_name_submitted)
        self.buttons = []
        for name, func in actions:
            button = z.Button(name, focus_parent=self.focus)
            button.clicked.connect(lambda f, i, d, func=func: func())
            self.buttons.append(button)
        self.spacer = z.Spacer()
        self.head = z.Flex(children=[
            z.FlexChild(self.name_input.layout),
            *[z.FlexChild(x.layout) for x in self.buttons],
            z.FlexChild(self.spacer.layout, flex=1)
        ])
        self.input = z.Input(text=code['code'], focus_parent=self.focus, tabs=True,
                                     multiline=True, actions=[
            ('copy', self.copy_to_clipboard),
            ('paste', self.paste_from_clipboard),
        ])
        self.input.submitted.connect(self.on_code_submitted)
        self.column = z.Flex([z.FlexChild(self.head.layout), z.FlexChild(self.input.layout)], axis='y', xalign='largest')
        self.layout = self.column.layout

        self.output_view = None

    def get_name(self):
        return f'Code: {self.code["id"]}'

    def copy_to_clipboard(self):
        world.apps['Clipboard'].set_text(self.input.text)

    def paste_from_clipboard(self):
        self.input.set_text(world.apps['Clipboard'].get_text())

    def update_code(self):
        self.code = world.codes.get_code(self.code['id'])
        self.input.set_text(self.code['code'])

    def edit_triggered(self):
        world.codes.edit_code(self.code)
        self.update_code()

    def archive_triggered(self):
        world.codes.archive_code(self.code)
        world.floaties.drop_obj(self)

    def on_name_submitted(self):
        self.code['name'] = self.name_input.text
        world.codes.update_code_name(self.code)

    def on_code_submitted(self):
        self.code['code'] = self.input.text
        world.codes.update_code(self.code)
        self.update_code()

    def ast_triggered(self):
        AstNodeView = world.classes.get_class(name='AstNodeView')
        world.floaties.add(AstNodeView(ast.parse(self.code['code'])))

    def run_triggered(self):
        kernel = world.kernels.ensure_kernel(self.code['kernel'])
        try:
            result = kernel.send_code(self.code, catch_errors=False)
        except Exception as e:
            world.floaties.add(z.PyErrorView(e))
        else:
            if result['output']:
                if not self.output_view:
                    CodeOutputView = world.classes['CodeOutputView']
                    self.output_view = CodeOutputView()
                    self.output_view.dropped.connect(self.on_output_view_dropped)
                    world.floaties.add(self.output_view)
                self.output_view.set_output(result['output'])

    def on_output_view_dropped(self):
        self.output_view = None

    def drop(self):
        self.column.drop()
        self.head.drop()
        self.name_input.drop()
        self.spacer.drop()
        self.input.drop()
        for button in self.buttons:
            button.drop()
        self.focus.drop()

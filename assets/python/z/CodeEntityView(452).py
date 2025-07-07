class CodeEntityView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity

        self.actions_panel = z.ActionsPanel([
            ('run code', self.run_code),
            ('paste code', self.paste_code),
            ('edit name', self.edit_name),
            ('edit language', self.edit_lang),
            ('edit kernel', self.edit_kernel),
            ('copy entity', self.entity.copy),
            ('clone', self.clone_code),
            ('archive', self.archive_code),
            ('delete', self.delete_code),
        ], focus_parent=self.focus)

        self.code_input = z.Input(self.entity.code_str, multiline=True,
                                  tabs=True, focus_parent=self.focus,
                                  min_lines=3, max_lines=10, syntax_coloring=True)
        self.code_input.submitted.connect(self.code_input_submitted)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.code_input.layout, flex=1)
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def code_input_submitted(self):
        self.entity.set_code_str(self.code_input.text)
        self.entity.save()

    def __str__(self):
        return f'{self.entity}, [name={self.entity.name}, lang={self.entity.lang}, kernel={self.entity.kernel}]'

    def paste_code(self):
        assert Y.register_type == 'entity'
        entity = Y.value
        assert entity.type == 'code'
        new_code_str = '\n'.join((self.code_input.text, entity.code_str))
        self.code_input.set_text(new_code_str)
        self.code_input_submitted()

    def run_code(self):
        self.entity.run()

    def edit_name(self):
        input = z.Input(self.entity.name)
        def on_submitted():
            new_name = input.text.strip()
            if new_name != self.entity.name:
                self.entity.name = new_name
                self.entity.save()
        input.submitted.connect(on_submitted)
        world.floaties.add(input)

    def edit_lang(self):
        input = z.Input(self.entity.lang)
        def on_submitted():
            new_lang = input.text.strip()
            if new_lang != self.entity.lang:
                self.entity.lang = new_lang
                self.entity.save()
        world.floaties.add(input)

    def edit_kernel(self):
        input = z.Input(str(self.entity.kernel) if self.entity.kernel else '')
        def on_submitted():
            new_kernel = input.text.strip()
            if new_kernel:
                new_kernel = int(new_kernel)
                if new_kernel != self.entity.kernel:
                    self.entity.kernel = new_kernel
                    self.entity.save()
        world.floaties.add(input)

    def clone_code(self):
        cloned = self.entity.clone()
        world.floaties.add(cloned.view(cloned))

    def archive_code(self):
        self.entity.archive()

    def delete_code(self):
        self.entity.delete()

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.code_input.drop()
        self.focus.drop()

import re, ast

class ClassView:
    def __init__(self, cls, instance=None, focus_parent=world.focus, max_lines=20, min_lines=20):
        self.cls = cls
        self.instance = instance
        self.focus = focus_parent.add_child(self)
        self.name = z.ReactiveValue(self.make_name())
        actions = [
            ('get code', self.get_code_view_triggered),
            ('edit', self.edit_triggered),
            ('reset', self.reset_triggered),
            ('launch as floatie', self.launch_triggered),
            ('delete', self.delete_triggered)
        ]
        self.project_id_input = z.Input(text=str(self.cls['project_id']), focus_parent=self.focus)
        self.project_id_input.submitted.connect(self.project_id_submitted)
        self.kernel_input = z.Input(text=str(self.cls['kernel']), focus_parent=self.focus)
        self.kernel_input.submitted.connect(self.kernel_submitted)
        self.actions_panel = world.classes.get_class(name='ActionsPanel')(actions, focus_parent=self.focus)
        self.row = z.Flex([z.FlexChild(self.project_id_input.layout),
                           z.FlexChild(self.kernel_input.layout),
                           z.FlexChild(self.actions_panel.layout)],
                           yalign='largest')
        self.input = z.Input(text=self.cls['code'], focus_parent=self.focus, tabs=True, multiline=True, max_lines=max_lines, min_lines=min_lines, syntax_coloring=True)
        self.input.submitted.connect(self.input_submitted)
        self.column = z.Flex([z.FlexChild(self.row.layout), z.FlexChild(self.input.layout, flex=1)], axis='y', xalign='largest')
        self.layout = self.column.layout

        self.changed = z.Signal()

        world.focus.set_focus(self.input.focus)

    def make_name(self):
        return f"class: {self.cls['name']}"

    def project_id_submitted(self):
        value = int(self.project_id_input.text)
        world.classes.update_class_code(self.cls['id'], project_id=value)
        self.cls['project_id'] = value

    def kernel_submitted(self):
        value = int(self.kernel_input.text)
        world.classes.update_class_code(self.cls['id'], kernel=value)
        self.cls['kernel'] = value

    #def update_instance(self):
    #    if self.instance:
    #        self.instance.__class__ = world.classes[self.cls['name']]

    def input_submitted(self):
        new_code_str = self.input.text.strip()
        ast.parse(new_code_str)
        new_name = self.scrape_class_name(new_code_str) or self.cls['name']
        # side effect in update_class_code updates self.cls
        world.classes.update_class_code(self.cls['id'], code_str=new_code_str, new_name=new_name)
        self.name.set(self.make_name())
        #self.update_instance()
        self.changed.emit(self.cls)#world.classes[self.cls['name']])

    #def method_code_submitted(self, method, new_code_str):
    #    new_func = ast.parse(new_code_str).body[0]
    #    for n in self.tree.body:
    #        if isinstance(n, ast.ClassDef):
    #            for (i, nn) in enumerate(n.body):
    #                if nn is method:
    #                    n.body[i] = new_func
    #                    break
    #    self.cls['code'] = ast.unparse(self.tree)
    #    world.classes.update_class_code(self.cls['id'], code_str=self.cls['code'])
    #    self.update_methods()

    def reset_triggered(self):
        world.classes.reset_class(self.cls['id'])

    def scrape_class_name(self, text):
        m = re.search('class\\s+(\\w+)\\s*(\\(.*\\))?:', text)
        return m.group(1) if m else None

    def get_code_view_triggered(self):
        CodeView = world.classes.get_class(name='CodeView')
        world.floaties.add(CodeView(world.classes.codes[self.cls['id']]))

    def launch_triggered(self):
        world.floaties.add(world.classes.get_class(self.cls['id'])())

    def delete_triggered(self):
        world.classes.delete_class_code(self.cls['id'])
        world.floaties.drop_obj(self)

    def edit_triggered(self):
        new_code_str = world.dialogs.edit_string(self.cls['code'], file_suffix='.py').strip()
        try:
            ast.parse(new_code_str)
            new_name = self.scrape_class_name(new_code_str)
            self.cls['code'] = new_code_str
            self.cls['name'] = new_name if new_name else self.cls['name']
            world.classes.update_class_code(self.cls['id'], code_str=self.cls['code'], new_name=self.cls['name'])
            self.name.set(self.make_name())
            self.input.set_text(self.cls['code'])
            #self.update_instance()
        except Exception as e:
            world.floaties.add(z.PyErrorView(e))

    def drop(self):
        self.column.drop()
        self.row.drop()
        self.actions_panel.drop()
        self.project_id_input.drop()
        self.kernel_input.drop()
        self.input.drop()
        self.focus.drop()

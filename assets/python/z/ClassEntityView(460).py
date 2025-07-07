import ast, re


class ClassEntityView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity

        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.entity.copy),
            ('paste method', self.paste_method_triggered),
            ('launch as floatie', self.launch_triggered),
            ('clone', self.clone),
            ('delete', self.delete_class),
        ], focus_parent=self.focus)

        self.code_input = z.Input(self.entity.code_str, multiline=True, min_lines=3, max_lines=10, syntax_coloring=True, tabs=True)
        self.code_input.submitted.connect(self.code_input_submitted)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.code_input.layout, flex=1)
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def code_input_submitted(self):
        new_code_str = self.code_input.text.strip()
        ast.parse(new_code_str)
        new_name = self.entity.name
        m = re.search('class\\s+(\\w+)\\s*(\\(.*\\))?:', new_code_str)
        if m:
            new_name = m.group(1)
        self.entity.code_str = new_code_str
        self.entity.name = new_name
        self.entity.save()

    def paste_method_triggered(self):
        assert Y.register_type == 'entity'
        entity = Y.value
        assert entity.type in ('code', 'function')
        if entity.type == 'code':
            wrapped_code = f"def new_method(self):\n" + "\n".join(f"    {line}" for line in entity.code_str.splitlines())
            wrapped_ast = ast.parse(wrapped_code)
            new_method = wrapped_ast.body[0]
            assert isinstance(new_method, ast.FunctionDef)
        else:
            raise NotImplementedError
        class_ast = ast.parse(self.code_input.text)
        for node in class_ast.body:
            if isinstance(node, ast.ClassDef):
                node.body.append(new_method)
                break
        else:
            raise ValueError("No class definition found in the provided class code.")
        new_class_code = ast.unparse(class_ast)
        self.code_input.set_text(new_class_code)
        self.entity.code_str = new_class_code
        self.entity.save()

    def launch_triggered(self):
        world.floaties.add(self.entity.eval()())

    def __str__(self):
        return str(self.entity)

    def clone(self):
        cloned = self.entity.clone()
        world.floaties.add(cloned.view(cloned))

    def delete_class(self):
        self.entity.delete()

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.code_input.drop()
        self.focus.drop()

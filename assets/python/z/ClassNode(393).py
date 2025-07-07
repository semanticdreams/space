import ast
class ClassNode(z.DynamicGraphNode):
    def __init__(self, cls_data):
        super().__init__(
            key = f'class:{cls_data["id"]}',
            label='cls_data["name"]',
            color=(1, 0.4, 0, 1),
            sub_color=(1, 0.4, 0, 1),
        )

#    def builder(self, context):
#        self.input = z.Input(text=self.cls_data['code'],
#                             focus_parent=context['focus_parent'],
#                             multiline=True, min_lines=8,
#                             max_lines=20)
#        self.input.submitted.connect(self.input_submitted)
#        self.layout = self.input.layout
#
#    def scrape_class_name(self, text):
#        m = re.search('class\\s+(\\w+)\\s*(\\(.*\\))?:', text)
#        return m.group(1) if m else None
#
#    def input_submitted(self):
#        new_code_str = self.input.text.strip()
#        ast.parse(new_code_str)
#        self.cls_data['code'] = new_code_str
#        self.cls_data['name'] = self.scrape_class_name(self.cls_data['code']) \
#            or self.cls_data['name']
#        world.classes.update_class_code(self.cls_data['id'], code_str=self.cls_data['code'], new_name=self.cls_data['name'])
#
#    def drop(self):
#        self.input.drop()

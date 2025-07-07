class AgentOneView:
    def __init__(self):
        self.agent_one = z.AgentOne()
        self.focus = world.focus.add_child(self)
        self.output = z.Input(focus_parent=self.focus,
            multiline=True, max_lines=30, min_lines=30)
        self.input = z.Input(focus_parent=self.focus,
            min_lines=3, max_lines=5, multiline=True)
        self.submit_button = z.Button('submit', focus_parent=self.focus)
        self.submit_button.clicked.connect(self.on_submit)
        self.bottom = z.Flex([
            z.FlexChild(self.input.layout, flex=1),
            z.FlexChild(self.submit_button.layout)
        ], yalign='largest')
        self.column = z.Flex([
            z.FlexChild(self.output.layout),
            z.FlexChild(self.bottom.layout)
        ], axis='y', xalign='largest')
        self.layout = self.column.layout
        
    def on_submit(self, f, i, d):
        self.submit_button.set_text('...')
        world.aio.create_task(self.agent_one.submit(self.input.text),
            self.callback)
            
    def callback(self, result):
        self.submit_button.set_text('submit')
        self.output.set_text(result['content'])
        
    def drop(self):
        self.column.drop()
        self.output.drop()
        self.bottom.drop()
        self.input.drop()
        self.submit_button.drop()
        self.focus.drop()
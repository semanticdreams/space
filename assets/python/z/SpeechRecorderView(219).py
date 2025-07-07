class SpeechRecorderView:
    def __init__(self):
        world.apps.ensure_app('SpeechRecorder')
        self.focus = world.focus.add_child(self)
        actions = [
            ('rec', self.rec),
        ]
        self.actions_panel = world.classes['ActionsPanel'](actions, self.focus)

        self.input = z.Input(multiline=True, max_lines=5,
                                     focus_parent=self.focus)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.input.layout),
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def rec(self):
        result = world.apps['SpeechRecorder'].listen_and_recognize()
        self.input.set_text(result['text'])

    def drop(self):
        self.column.drop()
        self.input.drop()
        self.actions_panel.drop()
        self.focus.drop()

class SubprocessKernelView:
    def __init__(self, kernel):
        self.kernel = kernel
        self.name = z.ReactiveValue(self.make_name())
        self.focus = world.focus.add_child(self)
        self.name_input = z.Input(text=self.kernel.name or '', focus_parent=self.focus)
        self.name_input.submitted.connect(self.name_submitted)
        actions = [
            ('env', self.env_triggered),
            ('delete', self.delete_triggered),
            ('status', self.update_status),
            ('start', self.kernel.start_kernel),
            ('stop', self.kernel.stop_kernel),
            ('wait-for-stopped', self.kernel.wait_for_kernel_stopped),
        ]
        self.actions_panel = z.ActionsPanel(actions, self.focus)
        self.row = z.Flex(children=[
            z.FlexChild(self.name_input.layout),
            z.FlexChild(self.actions_panel.layout)
        ])

        self.cmd_input = z.Input(text=self.kernel.cmd or '', focus_parent=self.focus)
        self.cmd_input.submitted.connect(self.cmd_submitted)
        self.cwd_input = z.Input(text=self.kernel.cwd or '', focus_parent=self.focus)
        self.cwd_input.submitted.connect(self.cwd_submitted)

        self.status_label = z.Label('status: ')

        self.column = z.Flex(xalign='largest', axis='y', children=[
            z.FlexChild(self.row.layout),
            z.FlexChild(self.cmd_input.layout),
            z.FlexChild(self.cwd_input.layout),
            z.FlexChild(self.status_label.layout),
        ])
        self.layout = self.column.layout

        self.update_status()

    def update_status(self):
        status_str = self.kernel.status
        if self.kernel.status == 'started':
            if self.kernel.is_kernel_alive():
                status_str += ', alive'
            else:
                status_str += ', dead'
        self.status_label.text.set(f'status: {status_str}')

    def make_name(self):
        return f'kernel: {self.kernel.id} {self.kernel.name}'

    def raise_for_internal_kernel(self):
        if self.kernel.id == 0:
            raise Exception('can\'t change internal kernel')

    def env_triggered(self):
        world.floaties.add(world.classes.get_class(name='PyDictView')(self.kernel.env))

    def delete_triggered(self):
        self.raise_for_internal_kernel()
        self.kernel.delete_kernel()
        world.floaties.drop_obj(self)

    def name_submitted(self):
        self.raise_for_internal_kernel()
        self.kernel.update_data(name=self.name_input.text)
        self.name.set(self.make_name())

    def cmd_submitted(self):
        self.raise_for_internal_kernel()
        self.kernel.update_data(cmd=self.cmd_input.text)

    def cwd_submitted(self):
        self.raise_for_internal_kernel()
        self.kernel.update_data(cwd=self.cwd_input.text)

    def drop(self):
        self.column.drop()
        self.cmd_input.drop()
        self.cwd_input.drop()
        self.status_label.drop()
        self.row.drop()
        self.name_input.drop()
        self.actions_panel.drop()
        self.focus.drop()
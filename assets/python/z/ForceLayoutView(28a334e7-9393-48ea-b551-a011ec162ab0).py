class ForceLayoutView:
    def __init__(self, force_layout, focus_parent=world.focus):
        self.focus = focus_parent.add_child(self)
        self.force_layout =  force_layout
        self.force_layout.changed.connect(self.force_layout_changed)

        self.params_changed = z.Signal()

        self.repulsive_force_input = z.Input(
            str(self.force_layout.repulsive_force_constant),
            focus_parent=self.focus
        )
        self.repulsive_force_input.submitted.connect(self.on_repulsive_force_input_submitted)
        self.spring_rest_length_input = z.Input(
            str(self.force_layout.spring_rest_length),
            focus_parent=self.focus
        )
        self.spring_rest_length_input.submitted.connect(self.on_spring_rest_length_input_submitted)
        self.spring_constant_input = z.Input(
            str(self.force_layout.spring_constant),
            focus_parent=self.focus
        )
        self.spring_constant_input.submitted.connect(self.on_spring_constant_input_submitted)
        self.max_displacement_squared_input = z.Input(
            str(self.force_layout.max_displacement_squared),
            focus_parent=self.focus
        )
        self.max_displacement_squared_input.submitted.connect(self.on_max_displacement_squared_input_submitted)

        self.center_force_input = z.Input(
            str(self.force_layout.center_force),
            focus_parent=self.focus
        )
        self.center_force_input.submitted.connect(self.on_center_force_input_submitted)

        self.stabilized_max_displacement_input = z.Input(
            str(self.force_layout.stabilized_max_displacement),
            focus_parent=self.focus
        )
        self.stabilized_max_displacement_input.submitted.connect(self.on_stabilized_max_displacement_input_submitted)

        self.stabilized_avg_displacement_input = z.Input(
            str(self.force_layout.stabilized_avg_displacement),
            focus_parent=self.focus
        )
        self.stabilized_avg_displacement_input.submitted.connect(self.on_stabilized_avg_displacement_input_submitted)

        self.params_row = z.Flex([
            z.FlexChild(self.repulsive_force_input.layout),
            z.FlexChild(self.spring_rest_length_input.layout),
            z.FlexChild(self.spring_constant_input.layout),
            z.FlexChild(self.max_displacement_squared_input.layout),
            z.FlexChild(self.center_force_input.layout),
            z.FlexChild(self.stabilized_max_displacement_input.layout),
            z.FlexChild(self.stabilized_avg_displacement_input.layout),
        ], yalign='largest')

        self.active_label = z.Label(str(self.force_layout.active))
        self.start_button = z.Button('start', on_click=lambda f, i, d: self.force_layout.start())
        self.stop_button = z.Button('stop', on_click=lambda f, i, d: self.force_layout.stop())

        self.control_row = z.Flex([
            z.FlexChild(self.active_label.layout),
            z.FlexChild(self.start_button.layout),
            z.FlexChild(self.stop_button.layout),
        ], yalign='largest')

        self.column = z.Flex([
            z.FlexChild(self.control_row.layout),
            z.FlexChild(self.params_row.layout, flex=1),
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def force_layout_changed(self):
        self.active_label.set_text(str(self.force_layout.active))

    def on_repulsive_force_input_submitted(self):
        self.force_layout.repulsive_force_constant = int(self.repulsive_force_input.text)
        self.params_changed.emit()

    def on_spring_rest_length_input_submitted(self):
        self.force_layout.spring_rest_length = int(self.spring_rest_length_input.text)
        self.params_changed.emit()

    def on_spring_constant_input_submitted(self):
        self.force_layout.spring_constant = int(self.spring_constant_input.text)
        self.params_changed.emit()

    def on_max_displacement_squared_input_submitted(self):
        self.force_layout.max_displacement_squared = int(self.max_displacement_squared_input.text)
        self.params_changed.emit()

    def on_center_force_input_submitted(self):
        self.force_layout.center_force = float(self.center_force_input.text)
        self.params_changed.emit()

    def on_stabilized_max_displacement_input_submitted(self):
        self.force_layout.stabilized_max_displacement = float(self.stabilized_max_displacement_input.text)
        self.params_changed.emit()

    def on_stabilized_avg_displacement_input_submitted(self):
        self.force_layout.stabilized_avg_displacement = float(self.stabilized_avg_displacement_input.text)
        self.params_changed.emit()

    def drop(self):
        self.force_layout.changed.disconnect(self.force_layout_changed)
        self.column.drop()
        self.control_row.drop()
        self.active_label.drop()
        self.start_button.drop()
        self.stop_button.drop()
        self.params_row.drop()
        self.repulsive_force_input.drop()
        self.spring_rest_length_input.drop()
        self.spring_constant_input.drop()
        self.max_displacement_squared_input.drop()
        self.center_force_input.drop()
        self.stabilized_max_displacement_input.drop()
        self.stabilized_avg_displacement_input.drop()
        self.focus.drop()


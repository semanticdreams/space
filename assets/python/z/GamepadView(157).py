class GamepadView:
    def __init__(self, gamepad):
        self.gamepad = gamepad
        self.focus = world.focus.add_child(self)
        self.button = z.ContextButton(
            color=(0.4, 0.2, 0.4, 1),
            focus_parent=self.focus, label=self.gamepad.name,
            actions=[
                ('rumble', self.rumble_triggered),
                ('battery', self.battery_triggered),
                ('disconnect', self.disconnect_triggered),
            ]
        )
        self.layout = self.button.layout
        self.spatiolator = self.button.spatiolator

    def rumble_triggered(self):
        #self.gamepad.rumble(0xffff, 0, 300)
        self.gamepad.rumble(0, 0xffff, 300)

    def battery_triggered(self):
        world.floaties.add(z.StringOutputView(str(self.gamepad.get_power_level())))

    def disconnect_triggered(self):
        self.gamepad.disconnect()

    def drop(self):
        self.button.drop()
        self.focus.drop()
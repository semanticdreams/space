import time


class Dov:
    def __init__(self, gamepad, callback, log_file=None):
        self.gamepad = gamepad
        self.callback = callback
        self.log_file = log_file

        self.left = z.DovDial()
        self.right = z.DovDial()

        #world.updated.connect(self.update)

    def update(self, delta):
        values = self.gamepad.get_axes()

        self.left.update(values[0], values[1])
        self.right.update(values[2], values[3])

        if values[0] or values[1] or values[2] or values[3]:
            #print(time.time(), 'update', self.gamepad.mac_address,
            #      self.left.active, self.left.stack, self.left.dialing, self.left.position, self.left.start_angle, self.left.sector_counts,
            #      self.right.active, self.right.stack, self.right.dialing, self.right.position, self.right.start_angle, self.right.sector_counts,
            #      file=self.log_file)

        if not self.left.active and not self.right.active and (self.left.stack or self.right.stack):
            inp = (tuple(self.left.stack), tuple(self.right.stack))
            self.callback(inp)
            self.reset()

    def dump(self):
        return {'sticks': (self.left.dump(), self.right.dump())}

    def reset(self):
        self.left.reset()
        self.right.reset()

    def drop(self):
        pass
        #self.log_file.close()
        #world.updated.disconnect(self.update)


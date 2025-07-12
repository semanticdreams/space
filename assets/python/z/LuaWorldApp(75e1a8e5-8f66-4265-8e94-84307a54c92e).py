class LuaWorldApp:
    def __init__(self):
        self.obj = z.LuaWorldView()

        self.obj.layout.position = np.array((-500, 0, -1000), float)
        self.obj.layout.rotation = transformations.quaternion_about_axis(
            math.pi * 0.5, (1, 0, 0))
        self.obj.layout.size = np.array((1000, 1000, 0), float)
        self.obj.layout.layouter()

    def drop(self):
        self.obj.drop()

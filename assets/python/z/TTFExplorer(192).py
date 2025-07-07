class TTFExplorer:
    def __init__(self):
        self.focus = world.focus.add_child(self)
        self.name = z.ReactiveValue('TTF Explorer')

    def drop(self):
        self.focus.drop()
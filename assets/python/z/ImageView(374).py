import os


class ImageView:
    def __init__(self, path):
        self.path = path
        self.pic = z.Pic(filename=self.path)
        self.focus = world.focus.add_child(self)
        self.layout = self.pic.layout

    def get_name(self):
        return f'image: {os.path.basename(self.path)}'

    def drop(self):
        self.pic.drop()
        self.focus.drop()
class Menus:
    def __init__(self):
        self.menus_list = []
        self.active_menu = None

        self.layout = z.Layout(measurer=self.measurer, layouter=self.layouter,
                                       uses_child_measures=True,
                                       name='menus')

        self.layout_root = z.LayoutRoot()
        self.layout.set_root(self.layout_root)

        self.root = self.create_menu(sort=True)
        world.apps['Clickables'].register_right_click_void_callback(lambda pos, ray: self.root.show(ray.origin + 200 * ray.direction))

    def update(self):
        self.layout_root.update()

    def measurer(self):
        for child in self.layout.children:
            child.measurer()

    def layouter(self):
        for child in self.layout.children:
            child.size = child.measure
            child.depth_offset_index = self.layout.depth_offset_index
            child.rotation = world.camera.camera.rotation
            child.layouter()

    def create_menu(self, *args, **kwargs):
        menu = z.Menu(*args, **kwargs)
        menu.closed.connect(lambda: self.menu_closed(menu))
        menu.opened.connect(lambda: self.menu_opened(menu))
        self.menus_list.append(menu)
        return menu

    def menu_closed(self, menu):
        menu.hide()
        self.active_menu = None

    def menu_opened(self, menu):
        self.active_menu = menu

    def drop(self):
        pass

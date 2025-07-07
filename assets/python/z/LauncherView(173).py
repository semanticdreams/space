class LauncherView:
    def __init__(self):
        self.launchable_codes = [x for x in z.CodeEntity.all() if x.launchable]

        self.focus = world.focus.add_child(obj=self)

        items = [(lambda x=x: self.launch_code(x), x.name)
                 for x in self.launchable_codes]

        items = sorted(items, key=lambda x: x[1])

        self.search_view = z.SearchView(items=items, focus_parent=self.focus, show_head=False)
        self.search_view.submitted.connect(self.on_submitted)

        self.layout = self.search_view.layout

    def __str__(self):
        return self.__class__.__name__

    def set_hud(self, hud):
        self.search_view.set_hud(hud)

    def launch_code(self, launchable_code):
        try:
            launchable_code.run()
        except Exception as e:
            world.floaties.add(z.PyErrorView(e))

    def close(self):
        world.floaties.drop_obj(self)

    def on_submitted(self, item):
        self.close()
        world.vim.set_current_mode('normal')
        item[0]()

    def intersect(self, ray):
        return self.input.intersect(ray)

    def drop(self):
        self.search_view.drop()
        self.focus.drop()

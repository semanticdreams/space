import os


class SkyboxBrowser:
    def __init__(self):
        self.focus = world.focus.add_child(obj=self)

        self.clear_button = z.Button('clear', focus_parent=self.focus)
        self.clear_button.clicked.connect(self.clear_clicked)

        self.top_row = z.Flex(children=[
            z.FlexChild(self.clear_button.layout),
        ])

        self.skyboxes_folder = space.getAssetPath('skyboxes')
        print(self.skyboxes_folder)
        names = os.listdir(self.skyboxes_folder)
        items = [(os.path.join(self.skyboxes_folder, x), x) for x in names]
        self.list_view = z.SearchView(items, focus_parent=self.focus, show_head=False)
        self.list_view.submitted.connect(self.on_submitted)

        self.column = z.Flex([z.FlexChild(self.top_row.layout),
                                      z.FlexChild(self.list_view.layout)], axis='y', xalign='largest')

        self.layout = self.column.layout

    def clear_clicked(self, f, i, d):
        world.renderers.skybox_renderer.set_skybox(None)

    def get_name(self):
        return 'skybox-browser'

    def on_submitted(self, item):
        world.renderers.skybox_renderer.set_skybox(item[0])

    def drop(self):
        self.column.drop()
        self.top_row.drop()
        self.clear_button.drop()
        self.list_view.drop()
        self.focus.drop()

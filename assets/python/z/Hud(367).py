class Hud:
    def __init__(self):
        self.camera = world.camera['identity']
       # self.camera.changed.connect(self.update_transform) (should be unnecessary for identity camera)

        world.hud_projection.changed.connect(self.hud_projection_changed)

        self.top_panel = z.HudPanel(color=(0.1, 0.1, 0.1, 1))
        self.bottom_panel = z.HudPanel(color=world.themes.theme.green[700])

        self.launcher_button = z.Button('icon:dashboard', hud=True, focusable=False, on_click=lambda f, i, d: world.apps['LauncherApp'].open_launcher())
        self.top_spacer = z.Spacer()
        self.top_panel.add(self.launcher_button)
        self.top_panel.add(self.top_spacer, flex=1)

        self.snackbar_host = z.SnackbarHost()

        self.worktop = z.Worktop()

        self.layout = z.Layout(children=[self.top_panel.layout,
                                                 self.bottom_panel.layout,
                                                 self.snackbar_host.layout,
                                                 self.worktop.layout],
                                       measurer=self.measurer,
                                       layouter=self.layouter,
                                       name='hud')
        self.hud_projection_changed()

        self.layout_root = z.LayoutRoot()
        self.layout.set_root(self.layout_root)
        self.layout.mark_measure_dirty()

        world.updated.connect(self.update)

    def update(self, dt):
        self.layout_root.update()

    def measurer(self):
        [x.measurer() for x in self.layout.children]
        self.layout.measure = np.array((0.0, 0.0, 0.0))

    def layouter(self):
        for child in self.layout.children:
            child.size = np.array((self.alignment.width, 5, 0), float)
            child.depth_offset_index = self.layout.depth_offset_index

        position = self.camera.position
        rotation = self.camera.rotation

        offset = -np.array(self.alignment.align_to_viewport([0, self.top_panel.layout.size[1], 0]))
        self.top_panel.layout.position = transformations.rotate_vector(rotation, np.array(offset)) + position

        offset = (-self.alignment.width/2, -self.alignment.height/2, -150)
        self.bottom_panel.layout.position = transformations.rotate_vector(rotation, np.array(offset)) + position

        self.snackbar_host.layout.size[0] = 60
        self.snackbar_host.layout.size[1] = self.snackbar_host.layout.measure[1]
        offset = (-self.alignment.width/2, -self.alignment.height/2 \
            + self.bottom_panel.layout.size[1] + 0.3, -150)
        self.snackbar_host.layout.position = transformations.rotate_vector(rotation, np.array(offset)) + position

        # worktop
        self.worktop.layout.size = np.array((
            self.alignment.width - 0.3 * 2, self.alignment.height - (5 * 2 + 0.6), 0
        ))
        offset = np.array((
            -self.alignment.width/2 - 0.3, -self.alignment.height/2 + self.bottom_panel.layout.size[1] + 0.3, -150
        ))
        self.worktop.layout.position = transformations.rotate_vector(rotation, offset) + position

        self.snackbar_host.layout.rotation = self.top_panel.layout.rotation = self.bottom_panel.layout.rotation = self.worktop.layout.rotation = rotation

        for child in self.layout.children:
            child.layouter()

    def hud_projection_changed(self):
        self.alignment = z.ViewportAlignment(150, projection=world.hud_projection)
        self.layout.mark_measure_dirty()

    def drop(self):
        world.updated.disconnect(self.update)
        self.layout.drop()
        self.snackbar_host.drop()
        self.top_panel.drop()
        self.top_spacer.drop()
        self.bottom_panel.drop()
        self.launcher_button.drop()

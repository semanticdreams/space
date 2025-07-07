from util import adjust_perceptual_color_brightness, get_luminance, wrap_text as wrap


class ContextButton:
    def __init__(self, _world=None, model=None, focus_parent=None, line_numbers=False, title=None,
                 label=None, color=None, actions=None, max_lines=None, focusable=True,
                 foreground_color=None, padding_insets=(1, 0.8), font_scale=2,
                 hud=False, data=None):
        self.focusable = focusable
        self.data = data
        self.line_numbers = line_numbers
        self.max_lines = max_lines
        self.title = title or ''
        self.world = world
        self.model = model
        self.hud = hud
        self.color = np.asarray(model.get_color() if model else (color if color is not None else world.themes.theme.button_background_color), float)
        self.unfocused_color = self.color.copy()

        if foreground_color is None:
            foreground_color = world.themes.theme.gray[900] if get_luminance(self.color) > 0.22 else world.themes.theme.gray[100]

        self.button = z.Button(background_color=self.color, focusable=False, hud=hud, wrap=80,
                                       padding_insets=padding_insets,
                                       font_scale=font_scale,
                                       centered=False, foreground_color=foreground_color,
                                       on_click=self.on_click, on_right_click=self.on_right_click)

        self.focus = None
        if focusable:
            self.focused = False
            self.focus = focus_parent.add_child(obj=self, on_changed=self.on_focus_changed) \
                    if focus_parent else world.focus.add_child(self, on_changed=self.on_focus_changed)

        self.actions = self.model.get_actions() if model else actions

        #if self.title:
        #    self.tooltip = world.tooltips.create_tooltip(self.button, self.title)
        #else:
        #    self.tooltip = None

        if model:
            self.label_model = model.get_label()
            if isinstance(self.label_model, str):
                self.label = self.label_model
            elif isinstance(self.label_model, z.ReactiveValue):
                self.label = self.label_model.get()
                self.label_model.changed.connect(self.label_changed)
            else:
                raise Exception('Unknown label model type: {}'.format(type(self.label_model)))
        else:
            self.label = label or ''

        self.button.set_text(wrap(self.label, max_lines=self.max_lines))

        if self.line_numbers:
            self.button.label.line_numbers = True

        #self.triggered = Signal()

        self.layout = self.button.layout

        self.spatiolator = z.Spatiolator(self.layout, self.button)

        if not self.hud:
            world.camera.debounced_camera_position.changed.connect(self.debounced_camera_position_changed)

    def set_hud(self, hud):
        if self.hud and not hud:
            world.camera.debounced_camera_position.changed.connect(self.debounced_camera_position_changed)
        elif not self.hud and hud:
            world.camera.debounced_camera_position.changed.disconnect(self.debounced_camera_position_changed)

        self.hud = hud
        self.button.set_hud(hud)

    def __repr__(self):
        return '<ContextButton: {}>'.format(self.title)

    def set_label(self, text):
        self.label = text
        self.button.set_text(wrap(self.label, max_lines=self.max_lines))

    def set_color(self, color):
        self.color = np.asarray(color, float)
        self.unfocused_color = self.color.copy()
        self.button.set_color(np.asarray(color, float))

    def on_focus_changed(self, value):
        assert self.focused != value
        self.focused = value
        if value:
            world.vim.modes['normal'].add_action_group(z.VimActionGroup('context-button', [
                z.VimAction('open menu', self.open_context_menu, sdl2.SDLK_BACKSLASH),
                z.VimAction('trigger', lambda: self.on_click(None, None, None), sdl2.SDLK_RETURN),
            ]))
        else:
            world.vim.modes['normal'].remove_action_group('context-button')

#        self.button.rectangle.set_color(adjust_perceptual_color_brightness(self.unfocused_color, 0.2 if value else 0))
        self.button.rectangle.set_color(world.themes.theme.focused_background_color \
                                        if value else self.unfocused_color)

    @classmethod
    def from_values(cls, **kwargs):
        return cls(**kwargs)
        class Model:
            def get_title(self): return title or ''
            def get_label(self): return label or ''
            def get_color(self): return color or (1, 0, 0, 1)
            def get_actions(self): return actions
        return cls(world, Model(), line_numbers=line_numbers, **kwargs)

    def open_context_menu(self, position=None):
        world.apps['Menus'].create_menu(self.actions, focus_parent=self.focus, hud=self.hud, position=self.button.layout.position if position is None else position).show()

    def on_right_click(self, pos, ray, intersection):
        if self.focusable:
            world.focus.set_focus(self.focus)
        self.open_context_menu(position=intersection - ray.direction * 0.2)

    def on_click(self, pos, ray, intersection):
        if self.focusable:
            world.focus.set_focus(self.focus)
        if self.actions:
            self.actions[0][1]()

    def intersect(self, ray):
        return self.button.intersect(ray)

    def label_changed(self):
        self.button.labels[0].text.set(self.label_model.get())

    #def on_click(self, pos, ray, intersection):
    #    self.triggered.emit()

    #@property
    #def position(self):
    #    return self.button.layout.position

    #def set_position(self, position):
    #    self.button.layout.set_position(position)

    #@property
    #def rotation(self):
    #    return self.button.layout.rotation

    #def set_rotation(self, rotation):
    #    self.button.layout.set_rotation(rotation)

    def debounced_camera_position_changed(self):
        return # TODO causes some problem
        if np.linalg.norm(self.button.layout.position - world.camera.debounced_camera_position.position) < 300:
            self.button.label.show_text()
        else:
            self.button.label.hide_text()

    def drop(self):
        if not self.hud:
            world.camera.debounced_camera_position.changed.disconnect(self.debounced_camera_position_changed)
        if isinstance(self.model and self.label_model, z.ReactiveValue):
            self.label_model.changed.disconnect(self.label_changed)
        self.button.drop()
        if self.focus:
            self.focus.drop()
        #if self.tooltip:
        #    world.tooltips.drop_tooltip(self.tooltip)


class ContextButtonLod1:
    def __init__(self, world, model, size=None):
        self.model = model
        self.rectangle = Rectangle(color=model.get_color())
        if hasattr(model, 'position'):
            self.rectangle.layout.set_position(model.position)
        size = size if size is not None else (20, 10, 1)
        self.rectangle.layout.set_constraints(BoxConstraints(min=size, max=size))
        self.focus = None

        self.layout = self.rectangle.layout
        self.spatiolator = Spatiolator(self.layout, self.rectangle)

    def updater(self):
        self.rectangle.updater()

    @property
    def position(self):
        return self.rectangle.layout.position

    @property
    def size(self):
        return self.rectangle.get_size()

    def set_position(self, position):
        self.rectangle.layout.set_position(position)

    def drop(self):
        self.rectangle.drop()
        if self.focus:
            self.focus.drop()

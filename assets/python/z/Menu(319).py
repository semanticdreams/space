import itertools


class Menu:
    counter = itertools.count()

    def __init__(self, actions=None, focus_parent=None, position=None, constraints=None, hud=False,
                 sort=False):
        self.id = next(self.counter)
        self.world = world
        self.actions = dict(actions or [])
        self.focus_parent = focus_parent
        self.position = position
        self.constraints = constraints
        self.sort = sort
        self.hud = hud
        self.layout = None

        self.active = False
        self.closed = z.Signal()
        self.opened = z.Signal()
        self.buttons = []

        self.submenus = {}

    def __repr__(self):
        return '<Menu: {}>'.format(self.id)

    def set_action(self, name, func):
        self.actions[name] = func

    def create_submenu(self, name, actions):
        menu = world.apps['Menus'].create_menu(actions)
        world.apps['Menus'].root.set_action(name, lambda: menu.show(position=self.position))
        self.submenus[name] = menu

    def destroy_submenu(self, name):
        world.apps['Menus'].destroy_menu(self.submenus[name])
        world.apps['Menus'].root.unset_action(name)

    def show(self, position=None):
        if not self.actions:
            return
        self.focus = self.focus_parent.add_child(obj=self) \
                if self.focus_parent else world.focus.add_child(obj=self)
        actions = sorted(self.actions) if self.sort else self.actions
        for name in actions:
            func = self.actions[name]
            button = z.Button(text=name, focus_parent=self.focus, centered=False, hud=self.hud)
            button.clicked.connect(lambda p, r, i, name=name: self.button_clicked(name))
            self.buttons.append(button)

        self.col = z.Flex([
            z.FlexChild(x.layout) for x in self.buttons
        ],
            axis='y', yalign='start', xalign='largest', yspacing=0)

        self.flipped = z.ViewportAwareFlipPositioner(self.col.layout)

        self.layout = self.flipped.layout
        world.apps['Menus'].layout.add_child(self.layout)

        self.layout.position = position if position is not None else self.position

        world.apps['Clickables'].register_left_click_void_callback(self.on_left_click_void)

        self.active = True

        self.layout.mark_measure_dirty()

        self.opened.emit()

    def on_left_click_void(self, pos, ray):
        self.close()

    def hide(self):
        world.apps['Clickables'].unregister_left_click_void_callback(self.on_left_click_void)
        self.active = False
        world.apps['Menus'].layout.remove_child(self.layout)
        self.flipped.drop()
        self.col.drop()
        for button in self.buttons:
            button.clicked.clear_callbacks()
            button.drop()
        self.buttons.clear()
        if self.focus:
            self.focus.drop()
        self.layout = None

    def button_clicked(self, name):
        self.close()
        self.actions[name]()

    def close(self):
        self.closed.emit()

    def drop(self):
        if self.active:
            self.hide()

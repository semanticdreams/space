import os


class FileSystemView:
    def __init__(self, path=None, focus_parent=world.focus):
        self.path = path or os.path.expanduser('~')
        self.show_hidden = False

        self.focus = focus_parent.add_child(self, on_subtree_changed=self.on_focus_subtree_changed)

        self.up_button = z.Button('^', focus_parent=self.focus)
        self.up_button.clicked.connect(self.up_button_clicked)

        self.current_path_button = z.ContextButton(focus_parent=self.focus)

        self.query = ''
        self.search_input = z.Input(focus_parent=self.focus)
        self.search_input.changed.connect(self.on_search_input_changed)

        self.head = z.Flex(yalign='largest',
            children=[
                z.FlexChild(self.up_button.layout),
                z.FlexChild(self.current_path_button.layout),
                z.FlexChild(self.search_input.layout, flex=1)
            ]
        )

        self.list_view = z.ListView(
            [],
            builder=self.builder,
            focus_parent=self.focus,
            show_head=False,
        )

        self.column = z.Flex([
            z.FlexChild(self.head.layout),
            z.FlexChild(self.list_view.layout, flex=1)
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

        self.go(self.path)

        self.submitted = z.Signal()

    def __str__(self):
        return f'<FileSystemView: {self.path}>'

    def on_focus_subtree_changed(self, focused):
        if focused:
            world.window.keyboard.connect(self.on_keyboard)
        else:
            world.window.keyboard.disconnect(self.on_keyboard)

    def on_keyboard(self, key, scancode, action, mods):
        if world.focus.current == self.search_input.focus:
            return
        if action == 1:
            if key == 104 and mods == 64:
                self.toggle_hidden()
            elif key in (sdl2.SDLK_BACKSPACE, sdl2.SDLK_LEFT):
                self.go_up()
            elif key == sdl2.SDLK_SLASH:
                world.focus.set_focus(self.search_input.focus)
                world.vim.set_current_mode('insert')
                world.vim._ignore_next_char = True
            elif key in (sdl2.SDLK_RIGHT, sdl2.SDLK_UP, sdl2.SDLK_DOWN):
                for child in self.list_view.column_focus.children:
                    if child.has_current_descendant():
                        if key == sdl2.SDLK_RIGHT:
                            self.go(child.obj.data)
                        elif key == sdl2.SDLK_DOWN:
                            world.focus.focus_next_sibling(child)
                        elif key == sdl2.SDLK_UP:
                            world.focus.focus_previous_sibling(child)
                        break

    def up_button_clicked(self, f, i, d):
        self.go_up()

    def go_up(self):
        self.go(os.path.dirname(self.path))

    def on_search_input_changed(self, value):
        self.query = value
        self.update_items(focus_list=False)

    def builder(self, item, context):
        filename = os.path.basename(item)
        root, ext = os.path.splitext(filename)
        is_file = os.path.isfile(item)
        actions = []
        if is_file:
            actions.append(('submit', lambda: self.submitted.emit(item)))
            if ext in ('.jpeg', '.jpg', '.png'):
                actions.append(('view image', lambda: world.floaties.add(z.ImageView(path=item))))
            else:
                actions.append(('edit', lambda: world.floaties.add(z.Editor(path=item))))
                actions.append(('edit with vim', lambda: world.dialogs.edit_file(item)))
        else:
            actions.append(('go', lambda: self.go(item)))
        actions.append(('pyobj', lambda: world.floaties.add(z.PyObjView(item))))
        actions.append(('with view', lambda: self.with_view(item)))
        return z.ContextButton(
            color=(0.9, 0.9, 0.3, 1) if is_file else (0.4, 0.9, 0.4, 1),
            label=filename,
            data=item,
            focus_parent=context['focus_parent'],
            actions=actions,
        )

    def with_view(self, item):
        picker = world.classes['ClassPicker']()
        def cb(code):
            world.floaties.drop_obj(picker)
            cls = world.classes[code['name']]
            world.floaties.add(cls(item))
        picker.submitted.connect(cb)
        world.floaties.add(picker)

    def get_children(self):
        return [os.path.join(self.path, x) for x in sorted(os.listdir(self.path))]

    def toggle_hidden(self):
        self.show_hidden = not self.show_hidden
        self.go(self.path)

    def go(self, item):
        if not os.path.isdir(item):
            return
        self.path = item
        self.is_file = os.path.isfile(self.path)
        self.search_input.set_text('')
        self.update_items()

    def update_items(self, focus_list=True):
        self.list_view.set_items([x for x in self.get_children()
                                  if (self.show_hidden or not os.path.basename(x).startswith('.')) \
                                  and z.fuzzy_match(self.query, os.path.basename(x))])
        self.current_path_button.set_label(self.path)
        if focus_list:
            world.focus.set_focus(self.list_view.focus)

    def drop(self):
        self.column.drop()
        self.head.drop()
        self.current_path_button.drop()
        self.search_input.drop()
        self.up_button.drop()
        self.list_view.drop()
        self.focus.drop()
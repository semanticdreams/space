class NormalVimMode(z.VimMode):
    def __init__(self):
        super().__init__('normal')

        self.input = None

        default_action_group = z.VimActionGroup('default', [
            z.VimAction('leader', self.set_current_mode_leader, sdl2.SDLK_SPACE),
            #z.VimAction('focus-next', self.focus_next, sdl2.SDLK_TAB),
            z.VimAction('dump-focus-tree', self.dump_focus_tree, sdl2.SDLK_F3),
        ])
        self.add_action_group(default_action_group)

        self.query = ''
        self.reset()

    def set_input(self, input):
        self.input = input

    def set_current_mode_leader(self):
        world.vim.set_current_mode('leader')

    def focus_next(self):
        world.focus.focus_next()

    def dump_focus_tree(self):
        world.focus.dump()

    def on_enter(self):
        pass

    def on_leave(self):
        pass

    def reset(self):
        self.operator = ''
        self.count = ''
        self.prefix = ''

    def on_controller_button_down(self, button):
        if button == sdl2.SDL_CONTROLLER_BUTTON_DPAD_RIGHT:
                world.focus.focus_right()
        elif button == sdl2.SDL_CONTROLLER_BUTTON_DPAD_LEFT:
                world.focus.focus_left()
        elif button == sdl2.SDL_CONTROLLER_BUTTON_DPAD_UP:
                world.focus.focus_up()
        elif button == sdl2.SDL_CONTROLLER_BUTTON_DPAD_DOWN:
                world.focus.focus_down()

    def on_character(self, char):
        if self.input:
            if self.operator == '/':
                self.query += chr(char)
                return
            elif self.operator == 'r':
                self.input.delete_char('right')
                self.input.insert_char(chr(char), move_caret=False)
                self.operator = ''
                return
        return super().on_character(char)

    def on_keyboard(self, key, scancode, action, mods):
        result = False
        if action == 1:
            if world.apps['Menus'].active_menu:
                if key == sdl2.SDLK_ESCAPE:
                    world.apps['Menus'].active_menu.close()
                    result = True
            elif key == sdl2.SDLK_TAB:
                if mods == 0:
                    world.focus.focus_next()
                elif mods in (1, 2):
                    world.focus.focus_previous()
            elif (key == sdl2.SDLK_h and mods in (1, 2)) or key == sdl2.SDLK_LEFT:
                world.focus.focus_left()
            elif (key == sdl2.SDLK_l and mods in (1, 2)) or key == sdl2.SDLK_RIGHT:
                world.focus.focus_right()
            elif (key == sdl2.SDLK_j and mods in (1, 2)) or key == sdl2.SDLK_DOWN:
                world.focus.focus_down()
            elif (key == sdl2.SDLK_k and mods in (1, 2)) or key == sdl2.SDLK_UP:
                world.focus.focus_up()
            elif self.input:
                result = True
                count = int(self.count) if self.count else None
                if key == sdl2.SDLK_ESCAPE:
                    self.reset()
                    self.query = ''
                elif self.operator == '/':
                    if key == sdl2.SDLK_BACKSPACE:
                        self.query = self.query[:-1]
                    elif key == sdl2.SDLK_RETURN:
                        self.operator = ''
                        self.input.search(self.query)
                elif self.operator == 'r':
                    pass
                elif mods == 65: # ctrl + shift
                    if key == sdl2.SDLK_c:
                        world.apps['Clipboard'].set_text(self.input.text)
                    elif key == sdl2.SDLK_v:
                        self.input.insert_text(world.apps['Clipboard'].get_text())
                elif key == sdl2.SDLK_y:
                    if self.operator == 'y':
                        Y('\n'.join(self.input.get_lines(count or 1)), 'V')
                        self.reset()
                    else:
                        self.operator = 'y'
                elif key == sdl2.SDLK_p:
                    regtype = Y.register_type
                    if regtype == 'v':
                        self.input.insert_text(Y.value)
                    elif regtype == 'V':
                        self.input.insert_text(Y.value, linewise=True)
                    else:
                        raise Exception(f'unsupported register type: {regtype}')
                elif key == sdl2.SDLK_i:
                    world.vim._ignore_next_char = True
                    world.vim.set_current_mode('insert')
                    self.reset()
                elif key == sdl2.SDLK_o:
                    if self.input.multiline:
                        if mods in (1, 2):
                            self.input.insert_char('\n')
                            world.vim._ignore_next_char = True
                            world.vim.set_current_mode('insert')
                            self.input.move_caret('up', 1)
                            self.input.match_indent()
                        else:
                            self.input.move_caret_to_line_end()
                            world.vim._ignore_next_char = True
                            world.vim.set_current_mode('insert')
                            self.input.move_caret('right', 1)
                            self.input.insert_char('\n')
                            self.input.match_indent()
                        self.reset()
                elif key == sdl2.SDLK_EQUALS:
                    if self.input.multiline:
                        self.input.match_indent()
                elif key == sdl2.SDLK_r:
                    world.vim._ignore_next_char = True
                    self.operator = 'r'
                elif key == sdl2.SDLK_SLASH:
                    world.vim._ignore_next_char = True
                    self.operator = '/'
                elif key == sdl2.SDLK_a:
                    if mods in (1, 2):
                        self.input.move_caret_to_line_end()
                    world.vim._ignore_next_char = True
                    world.vim.set_current_mode('insert')
                    self.input.move_caret('right', 1)
                    self.reset()
                elif key == sdl2.SDLK_h:
                    self.input.move_caret('left', count or 1)
                    self.reset()
                elif key == sdl2.SDLK_l:
                    self.input.move_caret('right', count or 1)
                    self.reset()
                elif key == sdl2.SDLK_j:
                    self.input.move_caret('down', count or 1)
                    self.reset()
                elif key == sdl2.SDLK_k:
                    self.input.move_caret('up', count or 1)
                    self.reset()
                elif key == sdl2.SDLK_n:
                    if self.query:
                        self.input.search(self.query, reverse=True if mods == 1 else False)
                elif key == sdl2.SDLK_w:
                    if not self.operator:
                        for _ in range(count or 1):
                            self.input.move_caret_to_next_word()
                    elif self.operator == 'd':
                        self.input.delete_n_next_words(count or 1)
                    elif self.operator == 'c':
                        self.input.delete_n_next_words(count or 1)
                        world.vim.set_current_mode('insert')
                        world.vim._ignore_next_char = True
                    self.reset()
                elif key == sdl2.SDLK_b:
                    for _ in range(count or 1):
                        self.input.move_caret_to_previous_word()
                    self.reset()
                elif key == sdl2.SDLK_c:
                    if not self.operator:
                        self.operator = 'c'
                elif key == sdl2.SDLK_d:
                    if self.operator == 'd':
                        Y('\n'.join(self.input.get_lines(count or 1)), 'V')
                        self.input.delete_lines(count or 1)
                        self.reset()
                    else:
                        self.operator = 'd'
                elif key == sdl2.SDLK_z:
                    if self.operator == 'z':
                        self.input.center_current_line()
                        self.reset()
                    elif not self.operator:
                        self.operator = 'z'
                elif key == sdl2.SDLK_x:
                    self.input.delete_char('right')
                    self.input.move_caret_to(self.input.caret_location)
                elif key == sdl2.SDLK_0:
                    if not self.count:
                        self.input.move_caret_to_line_start()
                    else:
                        self.count += '0'
                elif key == sdl2.SDLK_4 and mods in (1, 2):
                    self.input.move_caret_to_line_end()
                elif key == sdl2.SDLK_g and mods in (1, 2):
                    if count:
                        self.input.move_caret_to((self.input.caret_location[0], count-1))
                    else:
                        self.input.move_caret_to_last_line()
                    self.reset()
                elif key == sdl2.SDLK_1:
                    self.count += '1'
                elif key == sdl2.SDLK_2:
                    self.count += '2'
                elif key == sdl2.SDLK_3:
                    self.count += '3'
                elif key == sdl2.SDLK_4:
                    self.count += '4'
                elif key == sdl2.SDLK_5:
                    self.count += '5'
                elif key == sdl2.SDLK_6:
                    self.count += '6'
                elif key == sdl2.SDLK_7:
                    self.count += '7'
                elif key == sdl2.SDLK_8:
                    self.count += '8'
                elif key == sdl2.SDLK_9:
                    self.count += '9'
                elif key == sdl2.SDLK_g:
                    if not self.prefix:
                        self.prefix = 'g'
                    else:
                        self.input.move_caret_to_first_line()
                        self.reset()
                elif key == sdl2.SDLK_RETURN and mods == 64:
                    self.reset()
                    self.input.submit()
                else:
                    result = False
        if not result:
            result = super().on_keyboard(key, scancode, action, mods)
        return result

from contextlib import contextmanager

class Input:
    def __init__(self, text='', focus_parent=world.focus, multiline=False, tabs=False,
                 expandtab=True, tabstop=4, min_lines=3,
                 wrap_lines=True, syntax_coloring=False,
                 chars_per_line=None, max_lines=20, actions=None):
        self.dropped = False
        self.hud = False
        self.actions = actions
        self.multiline = multiline
        self.tabs = tabs
        self.expandtab = expandtab
        self.tabstop = tabstop
        self.chars_per_line = (80 if self.multiline else 8) if chars_per_line is None else chars_per_line
        self.max_lines = max_lines if self.multiline else 1
        self.min_lines = min_lines if self.multiline else 1
        self.num_lines = self.min_lines
        self.wrap_lines = wrap_lines
        self.inserting = False
        self.unsubmitted_change = False
        self.centered = not self.multiline

        self.style = z.TextStyle(color=world.themes.theme.input_foreground_color)

        self.submitted = z.Signal()
        self.changed = z.Signal()

        self.widget_actions = [
            ('yank', lambda: Y(self.text)),
            ('paste', lambda: self.set_text(str(world.apps['Store']['registers']['default']))),
            ('clear', lambda: self.set_text(''))
        ]

        self.hovered = False
        self.focused = False
        world.apps['Hoverables'].add_hoverable(self)
        world.apps['Clickables'].register(self)
        world.apps['Clickables'].register_right_click(self)

        self.rectangle = z.RRectangle(color=world.themes.theme.input_background_color)

        self.input_text = z.InputText(self, style=self.style, hud=self.hud,
                                      syntax_coloring=syntax_coloring)
        self.padding = z.Padding(self.input_text.layout, (0.5, 0.5))
        self.aligned = z.Aligned(self.padding.layout, axis='y',
                                 alignment='center' if self.centered else 'stretch')
        self.layout = self.aligned.layout

        self.focus = focus_parent.add_child(self, on_changed=self.on_focus_changed)

        self.set_text(text, emit_changed=False)

    def set_hud(self, hud):
        self.input_text.set_hud(hud)
        self.hud = hud

    def show_caret(self):
        self.input_text.show_caret()

    def hide_caret(self):
        self.input_text.hide_caret()

    def update_visible_text(self):
        self.input_text.update_visible_text()

    def update_rectangle(self):
        self.rectangle.set_size(self.layout.size)
        self.rectangle.set_rotation(self.layout.rotation)
        self.rectangle.set_position(self.layout.position)
        self.rectangle.set_depth_offset_index(self.layout.depth_offset_index)
        self.rectangle.update()

    def on_hovered(self, entered):
        if entered:
            world.apps['SystemCursors'].set_cursor('ibeam')
        else:
            world.apps['SystemCursors'].set_cursor('arrow')
        self.hovered = entered

    def intersect(self, ray):
        return self.layout.intersect(ray)

    def on_click(self, pos, ray, intersection):
        world.focus.set_focus(self.focus)

    def on_double_click(self, pos, ray, intersection):
        #world.vim.set_current_mode('insert')
        value = world.apps['Dialogs'].edit_string(self.text)
        if value is not None:
            self.set_text(value)
            self.submit()

    def on_right_click(self, pos, ray, intersection):
        actions = self.widget_actions if sdl2.SDLK_LSHIFT in world.window.keys or sdl2.SDLK_RSHIFT in world.window.keys else self.actions
        world.apps['Menus'].create_menu(actions, focus_parent=self.focus,
                                position=intersection - ray.direction * 0.2
                                #position=self.layout.position if position is None else position
                               ).show()

    def on_focus_changed(self, focused):
        self.focused = focused
        if focused:
            world.vim.modes['insert'].set_input(self)
            world.vim.modes['normal'].set_input(self)
            #world.vim.modes['normal'].add_action_group(z.VimActionGroup('input', [
            #    z.VimAction('insert', self.set_current_vim_mode_insert, sdl2.SDLK_i),
            #]))
            self.show_caret()
        else:
            world.vim.set_current_mode('normal')
            world.vim.modes['insert'].set_input(None)
            world.vim.modes['normal'].set_input(None)
            self.hide_caret()
        self.update_background_color()

    @contextmanager
    def inserting_ensured(self):
        prev = self.inserting
        self.set_inserting(True)
        try:
            yield
        finally:
            self.set_inserting(prev)

    def set_inserting(self, inserting):
        if inserting != self.inserting:
            self.inserting = inserting
            if not self.inserting:
                self.move_caret('left')

    def set_text(self, text, emit_changed=True):
        self.text = text
        self.lines = self.text.split('\n')
        if not self.lines:
            self.lines.append('')
        self.scroll_offset = [0, 0]
        self.caret_location = [0, 0]
        if emit_changed:
            self.text_changed()
        self.update_visible_text()

    def update_background_color(self):
        if self.focused:
            color = world.themes.theme.focused_background_color
        else:
            color = world.themes.theme.input_background_color
        self.rectangle.set_color(adjust_perceptual_color_brightness(
            color, 0.03 if self.unsubmitted_change else 0.0))
        self.rectangle.update()

    def text_changed(self):
        self.changed.emit(self.text)
        self.unsubmitted_change = True
        self.update_background_color()

    def submit(self):
        self.submitted.emit()
        self.unsubmitted_change = False
        self.update_background_color()

    def move_caret(self, direction, amount=1):
        location = self.caret_location.copy()
        if direction == 'up':
            location[1] -= amount
        elif direction == 'down':
            location[1] += amount
        elif direction == 'left':
            location[0] -= amount
        elif direction == 'right':
            location[0] += amount
        self.move_caret_to(location)

    def set_chars_per_line(self, chars_per_line):
        self.chars_per_line = chars_per_line
        self.scroll_offset[0] = max(self.caret_location[0] - self.chars_per_line + (0 if self.inserting else 1),
                                    min(self.scroll_offset[0], self.caret_location[0]))

    def set_num_lines(self, num_lines):
        self.num_lines = num_lines
        self.scroll_offset[1] = max(self.caret_location[1] - self.num_lines + 1,
                                    min(self.scroll_offset[1], self.caret_location[1]))

    def move_caret_to(self, location):
        old_scroll_offset = self.scroll_offset.copy()
        # Boundary adjustments
        self.caret_location[1] = max(0, min(location[1], len(self.lines) - 1))
        self.scroll_offset[1] = max(self.caret_location[1] - self.num_lines + 1,
                                    min(self.scroll_offset[1], self.caret_location[1]))
        current_line_length = len(self.lines[self.caret_location[1]])

        self.caret_location[0] = max(0, min(
            location[0], current_line_length if self.inserting else current_line_length - 1))
        self.scroll_offset[0] = max(self.caret_location[0] - self.chars_per_line + (0 if self.inserting else 1),
                                    min(self.scroll_offset[0], self.caret_location[0]))
        if self.scroll_offset != old_scroll_offset:
            self.update_visible_text()
        else:
            self.input_text.update_caret_rectangle()

    def center_current_line(self):
        self.scroll_offset[1] = max(0, self.caret_location[1] - self.num_lines // 2 + 1)
        self.update_visible_text()

    def move_caret_to_line_start(self):
        self.move_caret_to((0, self.caret_location[1]))

    def move_caret_to_line_end(self):
        self.move_caret_to((len(self.lines[self.caret_location[1]])-1, self.caret_location[1]))

    def move_caret_to_last_line(self):
        self.move_caret_to((self.caret_location[0], len(self.lines)-1))

    def move_caret_to_first_line(self):
        self.move_caret_to((self.caret_location[0], 0))

    def move_caret_to_end(self):
        self.move_caret_to((len(self.lines[-1]), len(self.lines)))

    def is_word_char(self, char):
        return char.isalnum() or char == '_'

    def move_caret_to_next_word(self):
        line = self.lines[self.caret_location[1]]
        for i in range(self.caret_location[0]+1, len(line)):
            if self.is_word_char(line[i]) != self.is_word_char(line[self.caret_location[0]]):
                for j in range(i, len(line)):
                    if not line[j].isspace():
                        self.move_caret_to((j, self.caret_location[1]))
                        return
        for i in range(self.caret_location[1]+1, len(self.lines)):
            line = self.lines[i]
            for j in range(0, len(line)):
                if not line[j].isspace():
                    self.move_caret_to((j, i))
                    return

    def move_caret_to_previous_word(self):
        line = self.lines[self.caret_location[1]]
        for i in range(self.caret_location[0]-1, -1, -1):
            if not line[i].isspace():
                for j in range(i, -1, -1):
                    if self.is_word_char(line[j]) != self.is_word_char(line[i]) or line[j].isspace():
                        self.move_caret_to((j+1, self.caret_location[1]))
                        return
                else:
                    self.move_caret_to((0, self.caret_location[1]))
                    return
        for i in range(self.caret_location[1]-1, -1, -1):
            line = self.lines[i]
            for j in range(len(line)-1, -1, -1):
                if not line[j].isspace():
                    for k in range(j, -1, -1):
                        if not self.is_word_char(line[k]) == self.is_word_char(line[j]):
                            self.move_caret_to((k+1, i))
                            return

    def delete_n_next_words(self, n):
        line = self.lines[self.caret_location[1]]
        start = end = self.caret_location[0]
        for _ in range(n):
            for i in range(end + 1, len(line)):
                if self.is_word_char(line[i]) != self.is_word_char(line[end]):
                    break
            else:
                end = len(line)
                break
            end = i
            for i in range(end, len(line)):
                if not line[i].isspace():
                    break
            end = i
            if end >= len(line):
                break
        self.lines[self.caret_location[1]] = line[:self.caret_location[0]] + line[end:]
        self.lines_changed()

    def search(self, text, reverse=False):
        """Move caret to next occurrence of text, loop back to beginning if necessary."""
        search_text = text.lower()
        if not reverse:
            for i in range(self.caret_location[1], len(self.lines)):
                line = self.lines[i]
                for j in range(self.caret_location[0] + 1, len(line)):
                    if line[j:].lower().startswith(search_text):
                        self.move_caret_to((j, i))
                        return
            for i in range(0, self.caret_location[1]):
                line = self.lines[i]
                for j in range(0, len(line)):
                    if line[j:].lower().startswith(search_text):
                        self.move_caret_to((j, i))
                        return
        else:
            # TODO this doesn't work
            for i in range(self.caret_location[1], -1, -1):
                line = self.lines[i]
                for j in range(self.caret_location[0] - 1, -1, -1):
                    if line[j::-1].lower().startswith(search_text):
                        self.move_caret_to((j, i))
                        return
            for i in range(len(self.lines)-1, self.caret_location[1], -1):
                line = self.lines[i]
                for j in range(len(line)-1, -1, -1):
                    if line[j::-1].lower().startswith(search_text):
                        self.move_caret_to((j, i))
                        return

    def match_indent(self):
        indent = 0
        if self.caret_location[1] > 0:
            prev_line = self.lines[self.caret_location[1]-1]
            indent = len(prev_line) - len(prev_line.lstrip(' '))
        self.lines[self.caret_location[1]] = ' ' * indent + self.lines[self.caret_location[1]].lstrip(' ')
        self.lines_changed()
        self.move_caret_to((indent, self.caret_location[1]))

    def insert_char(self, char, move_caret=True, trigger_update=True):
        line = self.lines[self.caret_location[1]]
        if char == '\n':
            self.lines[self.caret_location[1]] = line[:self.caret_location[0]]
            self.lines.insert(self.caret_location[1] + 1, line[self.caret_location[0]:])
            if move_caret:
                self.move_caret_to((0, self.caret_location[1] + 1))
        else:
            new_line = line[:self.caret_location[0]] + char + line[self.caret_location[0]:]
            self.lines[self.caret_location[1]] = new_line
            if move_caret:
                self.move_caret('right', 1)
        if trigger_update:
            self.lines_changed()

    def insert_text(self, text, linewise=False):
        with self.inserting_ensured():
            if linewise:
                self.move_caret_to((
                    len(self.lines[self.caret_location[1]]),
                    self.caret_location[1]
                ))
                self.insert_char('\n', trigger_update=False)
            for char in text:
                self.insert_char(char, move_caret=True, trigger_update=False)
        self.lines_changed()

    def delete_char(self, direction='left'):
        #self.lines = self.text.split('\n')
        line = self.lines[self.caret_location[1]]

        # Delete character to the left of the caret (backspace operation)
        if direction == 'left':
            if self.caret_location[0] > 0:
                new_line = line[:self.caret_location[0]-1] + line[self.caret_location[0]:]
                self.lines[self.caret_location[1]] = new_line
                self.move_caret('left', 1)
            elif self.caret_location[1] > 0: # has previous line
                new_location = (len(self.lines[self.caret_location[1]-1])-(0 if self.inserting else 1), self.caret_location[1]-1)
                self.lines[self.caret_location[1] - 1] += self.lines[self.caret_location[1]]
                del self.lines[self.caret_location[1]]
                self.move_caret_to(new_location)
         # Delete character to the right of the caret (delete operation)
        elif direction == 'right' and self.caret_location[0] < len(line):
            new_line = line[:self.caret_location[0]] + line[self.caret_location[0]+1:]
            self.lines[self.caret_location[1]] = new_line

        self.lines_changed()

    def lines_changed(self):
        self.text = '\n'.join(self.lines)
        self.text_changed()
        self.update_visible_text()

    def get_lines(self, n):
        return self.lines[self.caret_location[1]:self.caret_location[1]+n]

    def delete_lines(self, n):
        if len(self.lines) > 1:
            del self.lines[self.caret_location[1]:self.caret_location[1]+n]
            if not self.lines:
                self.lines.append('')
        else:
            self.lines = ['']
        self.text = '\n'.join(self.lines)
        self.text_changed()
        self.update_visible_text()
        self.move_caret_to(self.caret_location)

    def drop(self):
        world.apps['Clickables'].unregister(self)
        world.apps['Clickables'].unregister_right_click(self)
        if self.focus:
            self.focus.disconnect()
        self.aligned.drop()
        self.padding.drop()
        self.input_text.drop()
        self.rectangle.drop()
        world.apps['Hoverables'].remove_hoverable(self)
        self.focus.drop()
        self.dropped = True

import math


class Pagination:
    def __init__(self, num_items=0, per_page=5, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.first_button = z.Button('icon:first_page', focus_parent=self.focus, on_click=self.first_clicked)
        self.prev_button = z.Button('icon:chevron_left', focus_parent=self.focus, on_click=self.previous_clicked)
        self.next_button = z.Button('icon:chevron_right', focus_parent=self.focus, on_click=self.next_clicked)
        self.last_button = z.Button('icon:last_page', focus_parent=self.focus, on_click=self.last_clicked)

        style = z.TextStyle(color=world.themes.theme.gray[200], scale=1.5)

        self.page_label = z.Label(text_style=style)
        self.items_label = z.Label(text_style=style)

        self.spacer = z.Spacer()

        self.row = z.Flex(children=[
            z.FlexChild(self.first_button.layout),
            z.FlexChild(self.prev_button.layout),
            z.FlexChild(self.page_label.layout),
            z.FlexChild(self.spacer.layout, flex=1),
            z.FlexChild(self.items_label.layout),
            z.FlexChild(self.next_button.layout),
            z.FlexChild(self.last_button.layout)
        ], yalign='center')

        self.layout = self.row.layout

        self.num_items = num_items
        self.current_page = None
        self.per_page = per_page

        self.page_changed = z.Signal()

    def set_page(self, page, force_update=False):
        max_page = (self.num_items - 1) // self.per_page
        new_page = max(0, min(max_page, page))

        if page == self.current_page and not force_update:
            return

        self.current_page = new_page
        start_index = self.current_page * self.per_page
        stop_index = (self.current_page + 1) * self.per_page

        self.page_label.text.set(
            f'page: {new_page} / {max_page}')
        self.items_label.text.set(
            f'items: {start_index} - {stop_index-1} / {self.num_items-1}')

        self.page_changed.emit(
            dict(page=self.current_page,
                 slice=(start_index, stop_index)))

    def set_num_items(self, num_items):
        self.num_items = num_items
        self.set_page(0, force_update=True)

    def first_clicked(self, p, r, i):
        self.set_page(0)

    def last_clicked(self, p, r, i):
        self.set_page(math.inf)

    def previous_clicked(self, p, r, i):
        self.set_page(self.current_page - 1)

    def next_clicked(self, p, r, i):
        self.set_page(self.current_page + 1)

    def drop(self):
        self.row.drop()
        self.spacer.drop()
        self.first_button.drop()
        self.last_button.drop()
        self.next_button.drop()
        self.prev_button.drop()
        self.page_label.drop()
        self.items_label.drop()
        self.focus.drop()
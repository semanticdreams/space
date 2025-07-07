class XMLView:
    def __init__(self, xml):
        self.xml = xml
        self.xml.ensure_parsed()
        self.focus = world.focus.add_child(self)
        items = [(x, x.tag) for x in self.xml.elements]
        self.search_view = z.SearchView(items=items,
                                        builder=self.item_builder,
                                        focus_parent=self.focus)
        self.layout = self.search_view.layout

    @classmethod
    def from_text(cls, text):
        return cls(z.XML(text))

    def item_builder(self, item, context):
        return z.ContextButton(
            label=item[0].tag,
            focus_parent=context['focus_parent'],
            actions=[
                ('copy text', lambda item=item: Y(item[0].text)),
            ]
        )

    def drop(self):
        self.search_view.drop()
        self.focus.drop()

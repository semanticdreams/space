class CreateEntityView:
    def __init__(self, focus_parent=world.focus, on_submitted=None):
        self.focus = focus_parent.add_child(self)
        if on_submitted:
            self.on_submitted = on_submitted
        self.search_view = z.SearchView(
            items=self.get_entities(),
            focus_parent=self.focus
        )
        self.search_view.submitted.connect(self.on_submitted)
        self.layout = self.search_view.layout

    def get_entities(self):
        return [(v, k) for k, v in world.apps['Entities'].type_class_map.items()]

    def on_submitted(self, item):
        entity = item[0].create()
        #root_entity = world.apps['Entities'].get_entity('2')
        #root_entity.add_list_item(entity)
        #root_entity.save()
        G.add_node(entity)
        G.save()
        world.floaties.add(entity.view(entity))

    def drop(self):
        self.search_view.drop()
        self.focus.drop()

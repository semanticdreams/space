class Floaties:
    def __init__(self):
        setattr(world, 'floaties', self)

        self.floaties = {}
        self.changed = z.Signal()

        self.layout = z.Layout(measurer=self.measurer, layouter=self.layouter,
                                       #uses_child_measures=False,
                                       name='floaties')

        self.spacing = 1
        self.min_tile_size = np.array((5, 60, 0))
        self.row_heights = {}
        self.col_widths = {}
        self.tiles = {}
        self.next_free_tile = [0, 0]
        self.distance = 250

        self.to_hud = False

        self.on_projection_changed()
        world.projection.changed.connect(self.on_projection_changed)
        world.camera.camera.changed.connect(self.on_camera_changed)

        self.layout_root = z.LayoutRoot()
        self.layout.set_root(self.layout_root)
        self.layout.mark_measure_dirty()

    def on_projection_changed(self):
        self.alignment = z.ViewportAlignment(self.distance, projection=world.projection)
        self.layout.mark_measure_dirty()

    def on_camera_changed(self):
        self.layout.mark_layout_dirty()

    def update(self):
        self.layout_root.update()

    def measurer(self):
        #self.row_heights.clear()
        #self.col_widths.clear()
        for floatie in self.floaties.values():
            floatie.layout.measurer()
            #self.col_widths[floatie.tile[0]] = \
            #        max(self.col_widths.get(floatie.tile[0], self.min_tile_size[0]), floatie.layout.measure[0])
            #self.row_heights[floatie.tile[1]] = \
            #        max(self.row_heights.get(floatie.tile[1], self.min_tile_size[1]), floatie.layout.measure[1])

    def layouter(self):
        if not self.floaties:
            return
        width = max(x.measure[0]  for x in self.layout.children)
        offset = np.array((0, 0, 0), float)
        #offset += world.camera.camera.position
        offset[0] += self.alignment.width/2 - width
        offset[1] += self.alignment.height/2 - 7 - self.spacing
        offset[2] -= self.distance
        for i, floatie in enumerate(self.floaties.values()):
            offset[2] += i * 0.01
            #tile_size = np.array((self.col_widths[floatie.tile[0]], self.row_heights[floatie.tile[1]], 0))
            #floatie.layout.size = np.maximum(tile_size, floatie.layout.measure)
            floatie.layout.size = np.array((width, floatie.layout.measure[1], floatie.layout.measure[2]), float)
            offset[1] -= self.spacing + floatie.layout.size[1]
            #if not floatie.layout.position.any():
            floatie.layout.rotation = world.camera.camera.rotation
            floatie.layout.position = transformations.rotate_vector(floatie.layout.rotation, offset) + world.camera.camera.position
            try:
                floatie.layout.layouter()
            except Exception as e:
                raise
                #import traceback; print('err', traceback.format_exc())
                #world.next_tick(lambda e=e: (world.floaties.drop_obj(floatie.obj),
                #                             world.error_views.add(e)))

    def on_obj_moved(self, drag):
        for obj in world.apps['ObjectSelector'].selected:
            if obj.handle == drag.spatiolator.handle:
                for o in world.apps['ObjectSelector'].selected:
                    if o != obj:
                        o.set_position(
                            o.get_position() \
                            + (obj.get_position() - (drag.offset + drag.start_pos)))
        self.changed.emit()

    def add(self, o=None, code_entity=None):
        if o is None:
            o = eval(code_entity.code_str)
        floatie = z.Floatie(o, tuple(self.next_free_tile), code_entity)
        if self.to_hud:
            world.apps['Hud'].worktop.add(floatie)
            #self.floaties[floatie.obj] = floatie
        else:
            self.next_free_tile[0] += 1
            self.tiles[floatie.tile] = floatie
            self.floaties[floatie.obj] = floatie
            self.layout.add_child(floatie.layout)
            world.apps['ObjectSelector'].add_selectables([floatie])
            world.apps['Spatiolation'].add_spatiolatable(
                floatie,
                on_moved=self.on_obj_moved
            )
            self.layout.mark_measure_dirty()

        self.changed.emit()

        if not floatie.focus.has_current_descendant():
            world.focus.set_focus(floatie.focus)

        return floatie

    def drop_obj(self, o, emit_changed=True):
        floatie = self.floaties.pop(o)
        self.tiles.pop(floatie.tile)
        if floatie.tile[0] < self.next_free_tile[0]:
            self.next_free_tile[0] = floatie.tile[0]
        self.layout.remove_child(floatie.layout)
        world.apps['ObjectSelector'].remove_selectables([floatie])
        world.apps['Spatiolation'].remove_spatiolatable(floatie)
        floatie.drop()
        o.drop()
        self.layout.mark_measure_dirty()
        if emit_changed:
            self.changed.emit()

    def drop_all(self):
        for o, floatie in list(self.floaties.items()):
            self.drop_obj(o, emit_changed=False)
        self.changed.emit()

    def drop(self):
        self.drop_all()
        self.layout.drop()

class DynamicGraphApp:
    def __init__(self):
        world.vim.modes['apps'].add_action_group(
            z.VimActionGroup('dynamic-graph', [
                z.VimAction('dynamic-graph', self.run_dynamic_graph, sdl2.SDLK_g),
            ])
        )

    def run_dynamic_graph(self):
        world.vim.set_current_mode('normal')
        self.dynamic_graph = z.DynamicGraph()
        world.floaties.add(self.dynamic_graph)

    def drop(self):
        world.vim.modes['apps'].remove_action_group('dynamic-graph')

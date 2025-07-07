class KernelsSnacks:
    def __init__(self):
        world.kernels.changed.connect(self.kernels_changed)
        
    def kernels_changed(self):
        world.apps['Hud'].snackbar_host.show_message('Kernels changed')
        
    def drop(self):
        world.kernels.changed.disconnect(self.kernels_changed)
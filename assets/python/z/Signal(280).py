import gc


class Signal:
    def __init__(self):
        self.callbacks = []

    def emit(self, *args, **kwargs):
        try:
            for callback in list(self.callbacks):
                callback(*args, **kwargs)
        except Exception as e:
            world.report_error(e)

    def connect(self, callback):
        self.callbacks.append(callback)

    def disconnect(self, callback, not_connected_ok=False):
        if callback not in self.callbacks:
            if not_connected_ok:
                return
            raise ValueError('Callback not connected')
        self.callbacks.remove(callback)

    def clear_callbacks(self):
        self.callbacks = []

    @classmethod
    def get_all(cls):
        return [obj for obj in gc.get_objects() if isinstance(obj, Signal)]

    @classmethod
    def disconnect_all(cls):
        for signal in cls.get_all():
            signal.clear_callbacks()

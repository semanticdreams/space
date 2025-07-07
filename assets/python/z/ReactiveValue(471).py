class ReactiveValue:
    def __init__(self, value):
        self.value = value
        self.changed = z.Signal()

    def __str__(self):
        return str(self.value)

    def set(self, value):
        self.value = value
        self.changed.emit()

    def get(self):
        return self.value
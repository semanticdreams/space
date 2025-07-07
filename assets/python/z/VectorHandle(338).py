class VectorHandle:
    __slots__ = ('index', 'size')

    def __init__(self, index, size):
        self.index = index
        self.size = size
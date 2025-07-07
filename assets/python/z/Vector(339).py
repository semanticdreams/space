from collections import defaultdict


class Vector:
    __slots__ = ('array', 'freed', 'free_from')

    def __init__(self, size=0):
        self.array = np.zeros(size, np.float32)
        self.freed = defaultdict(list)
        self.free_from = 0

    def resize(self, size):
        if size > self.array.size:
            self.array.resize(size)
        elif size < self.array.size:
            raise ValueError("Manual downsizing is not supported.")

    def view(self, handle):
        return self.array[handle.index:handle.index+handle.size]

    def allocate(self, size):
        # Reuse freed
        if handles := self.freed[size]:
            handle = handles.pop()
            return handle
        index = self.free_from
        if self.free_from + size <= self.array.size:
            self.free_from += size
            return z.VectorHandle(index, size)
        self.array.resize(2 * self.array.size - self.free_from + size, refcheck=False)
        self.free_from += size
        return z.VectorHandle(index, size)

    def delete(self, handle):
        self.zero(handle)
        self.freed[handle.size].append(handle)

    def zero(self, handle):
        self.array[handle.index:handle.index+handle.size] = \
                np.zeros(handle.size)

    def reallocate(self, handle, new_size):
        if new_size < handle.size:
            start = handle.index + new_size
            end = handle.index + handle.size
            self.array[start:end] = 0
        elif new_size > handle.size:
            self.delete(handle)
            handle = self.allocate(new_size)
        return handle

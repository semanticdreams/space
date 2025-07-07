class DragMoveOperation:
    def __init__(self, spatiolator, start_pos, offset, plane):
        self.spatiolator = spatiolator
        self.start_pos = start_pos
        self.offset = offset
        self.plane = plane
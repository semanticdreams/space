class EdgeInsets:
    @staticmethod
    def all(value):
        return np.full(6, value, float)

    @staticmethod
    def only(x0=0, x1=0, y0=0, y1=0, z0=0, z1=0):
        return np.array((x0, y0, z0, x1, y1, z1), float)

    @staticmethod
    def symmetric(x=0, y=0, z=0):
        return np.array((x, y, z, x, y, z), float)

    @staticmethod
    def auto(values):
        n = len(values)
        if n == 1:
            return z.EdgeInsets.all(values[0])
        elif n == 2:
            return z.EdgeInsets.symmetric(x=values[0], y=values[1])
        elif n == 3:
            return z.EdgeInsets.symmetric(x=values[0], y=values[1], z=values[2])
        elif n == 4:
            return z.EdgeInsets.only(x0=values[0], x1=values[1], y0=values[2], y1=values[3])
        elif n == 6:
            return z.EdgeInsets.only(*values)
        else:
            raise Exception(f'invalid edge insets values: {values}')
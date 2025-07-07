class ErrorViews:
    def add(self, e):
        for o in world.floaties.floaties.keys():
            if isinstance(o, z.PyErrorView):
                if (type(e), e.args) == (type(o.error), o.error.args):
                    break
        else:
            world.floaties.add(z.PyErrorView(e))

    def drop(self):
        pass

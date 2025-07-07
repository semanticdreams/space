class SearchViewFromList:
    def __new__(cls, items=None, **kwargs):
        return z.SearchView(items=list(zip(items, items)), **kwargs)
class Droppable:
    def __getattribute__(self, name):
        if name in ('measurer', 'layouter'):
            assert not super().__getattribute__('dropped'), f'Can\'t acces {name}, object {self} dropped'
        return super().__getattribute__(name)

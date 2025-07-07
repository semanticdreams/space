import sqlite3
class SqliteDatabaseView:
    def __init__(self, path):
        self.focus = world.focus.add_child(self)
        self.path = path
        self.conn = sqlite3.connect(self.path)

        self.tables_list = z.ListView(self.get_tables(), focus_parent=self.focus)
        self.layout = self.tables_list.layout

    def get_tables(self):
        rows = self.conn.execute(
            "select name from sqlite_master where type='table';").fetchall()
        return [x[0] for x in rows]

    def drop(self):
        self.tables_list.drop()
        self.focus.drop()
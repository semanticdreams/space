import time


class DefaultViews:
    def __init__(self):
        pass

    def set_default_view(self, type_name, view_class_name, pos=0):
        current_time = int(time.time())
        cursor = world.db.cursor()
        cursor.execute(
            "SELECT id FROM default_views WHERE type_name = ? AND view_class_name = ?",
            (type_name, view_class_name)
        )
        row = cursor.fetchone()
        if row:
            # Update existing entry
            cursor.execute(
                """
                UPDATE default_views
                SET updated_at = ?, pos = ?
                WHERE id = ?
                """,
                (current_time, pos, row['id'])
            )
        else:
            # Insert new entry
            cursor.execute(
                """
                INSERT INTO default_views (type_name, view_class_name, pos, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (type_name, view_class_name, pos, current_time, current_time)
            )
        world.db.commit()

    def get_views(self, type_name):
        cursor = world.db.cursor()
        cursor.execute(
            """
            SELECT view_class_name
            FROM default_views
            WHERE type_name = ?
            ORDER BY pos ASC, updated_at DESC
            """,
            (type_name,)
        )
        views = [row['view_class_name'] for row in cursor.fetchall()]
        return views

    def drop(self):
        pass

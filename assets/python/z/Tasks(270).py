import time

class Tasks:
    def __init__(self):
        self.inbox_task_id = 56

    def create_task(self, label, points, parent):
        """Create a new task with given label, points and parent."""
        with world.db:
            return world.db.execute(
                'INSERT INTO tasks (label, points, parent) VALUES (?, ?, ?)',
                (label, points, parent)
            ).lastrowid

    def update_task_label(self, task_id, label):
        """Update the label of an existing task."""
        with world.db:
            return world.db.execute(
                'UPDATE tasks SET label = ? WHERE id = ?',
                (label, task_id)
            )

    def update_task_points(self, task_id, points):
        """Update the points of an existing task."""
        with world.db:
            return world.db.execute(
                'UPDATE tasks SET points = ? WHERE id = ?',
                (points, task_id)
            )

    def get_root_tasks(self):
        """Get all non-archived tasks that have no parent."""
        query = '''
            SELECT * FROM tasks 
            WHERE parent IS NULL AND archived_at IS NULL and done_at is null
            ORDER BY pos ASC
        '''
        return [dict(row) for row in world.db.execute(query).fetchall()]

    def get_child_tasks(self, task_id):
        """Get all non-archived child tasks for a given task ID."""
        return [
            dict(row) for row in 
            world.db.execute(
                'SELECT * FROM tasks WHERE parent = ? AND archived_at IS NULL and done_at is null',
                (task_id,)
            ).fetchall()
        ]

    def get_child_tasks_count(self, task_id):
        """Get the count of non-archived child tasks for a given task ID."""
        return world.db.execute(
            'SELECT COUNT(*) as count FROM tasks WHERE parent = ? AND archived_at IS NULL and done_at is null',
            (task_id,)
        ).fetchone()[0]

    def get_total_points(self):
        """Get the sum of points for all completed, non-archived tasks."""
        result = world.db.execute(
            '''
            SELECT SUM(points) as total_points
            FROM tasks
            WHERE done_at IS NOT NULL AND archived_at IS NULL
            '''
        ).fetchone()
        return result['total_points'] or 0

    def set_task_done(self, task_id, value):
        """Set task as done or not done by updating done_at timestamp."""
        with world.db:
            done_at = int(time.time()) if value else None
            return world.db.execute(
                'UPDATE tasks SET done_at = ? WHERE id = ?',
                (done_at, task_id)
            )

    def set_task_archived(self, task_id, value):
        """Set task as archived or not archived by updating archived_at timestamp."""
        with world.db:
            archived_at = int(time.time()) if value else None
            return world.db.execute(
                'UPDATE tasks SET archived_at = ? WHERE id = ?',
                (archived_at, task_id)
            )

    def get_total_points_since(self, since):
        """Sum points of done, non-archived tasks since a given time."""
        result = world.db.execute(
            '''
            SELECT SUM(points) as total_points
            FROM tasks
            WHERE done_at IS NOT NULL AND done_at >= ? AND archived_at IS NULL
            ''',
            (since,)
        ).fetchone()
        return result['total_points'] or 0

    def get_total_points_last_24h(self):
        """Get the sum of points for tasks completed in the last 24 hours."""
        since = int(time.time()) - 86400  # 24 * 60 * 60
        return self.get_total_points_since(since)

    def get_total_points_last_7d(self):
        """Get the sum of points for tasks completed in the last 7 days."""
        since = int(time.time()) - 7 * 86400
        return self.get_total_points_since(since)

    def drop(self):
        pass

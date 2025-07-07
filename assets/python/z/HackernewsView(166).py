import webbrowser
class HackernewsView:
    def __init__(self):
        self.hackernews = world.classes['Hackernews']()
        self.focus = world.focus.add_child(obj=self)

        actions=[
            ('top', self.get_top_stories_clicked),
            ('new', self.get_new_stories_clicked),
            ('best', self.get_best_stories_clicked),
            ('saved', self.get_saved_stories_clicked),
        ]
        self.actions_panel = world.classes['ActionsPanel'](actions, focus_parent=self.focus)

        self.story_list = world.classes['HackernewsStoryListView']([], self)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.story_list.layout)
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

        self.get_top_stories_clicked()

    def get_name(self):
        return 'Hackernews'

    def get_saved_stories_clicked(self):
        world.aio.create_task(
            self.hackernews.get_saved_stories(), lambda stories: self.story_list.set_stories(stories))

    def save_story(self, story):
        world.aio.create_task(self.hackernews.save_story(story['id']))

    def view_comments(self, story):
        world.aio.create_task(
            self.hackernews.get_story_comments(story),
            lambda comments: print(comments)
        )

    def open_story_in_browser(self, story):
        webbrowser.open(story['url'])

    def open_comments_in_browser(self, story):
        webbrowser.open(f'https://news.ycombinator.com/item?id={story["id"]}')

    def get_top_stories_clicked(self):
        world.aio.create_task(
            self.hackernews.get_stories('topstories'),
            lambda stories: self.story_list.set_stories(stories)
        )

    def get_new_stories_clicked(self):
        world.aio.create_task(
            self.hackernews.get_stories('newstories'),
            lambda stories: self.story_list.set_stories(stories)
        )

    def get_best_stories_clicked(self):
        world.aio.create_task(
            self.hackernews.get_stories('beststories'),
            lambda stories: self.story_list.set_stories(stories)
        )

    def close_story_dialog(self, story_list_dialog):
        world.floaties.drop_obj(story_list_dialog)

    def add_story_list(self, title, stories):
        story_list_dialog = world.classes['HackernewsStoryListView'](stories, self, title=title)
        world.floaties.add(story_list_dialog)

    def drop(self):
        self.column.drop()
        self.story_list.drop()
        self.actions_panel.drop()
        self.focus.drop()
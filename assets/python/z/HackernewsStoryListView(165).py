class HackernewsStoryListView:
    def __init__(self, stories, hackernews_cube, title=None):
        self.title = title
        self.hackernews_cube = hackernews_cube

        #def builder(story, **kwargs):
        #    print(story, kwargs)
        #    return z.ContextButton.from_values(
        #        title='hackernews story', label=story['title'], color=(1, 0.8, 0.3, 1),
        #        #position=self.world.unproject((*self.world.window.mouse_pos, 0.5)),
        #        actions=[
        #            ('save', lambda story=story: self.hackernews_cube.save_story(story)),
        #            ('view comments', lambda story=story: self.hackernews_cube.view_comments(story)),
        #            ('open story', lambda story=story: self.hackernews_cube.open_story_in_browser(story)),
        #            ('open comments', lambda story=story: self.hackernews_cube.open_comments_in_browser(story)),
        #        ])

        self.stories_list_view = z.ListView(stories, builder=world.classes['HackernewsStoryListItem'], show_head=False)

        self.layout = self.stories_list_view.layout

        self.focus = world.focus.add_child(self)

    def get_name(self):
        return f'Hackernews Stories: {self.title}'

    def set_stories(self, stories):
        self.stories_list_view.set_items(stories)

    def drop(self):
        self.stories_list_view.drop()
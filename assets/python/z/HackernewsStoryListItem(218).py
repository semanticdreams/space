class HackernewsStoryListItem:
    def __init__(self, item, context):
        self.item = item
        self.story_link = z.Link(self.item['title'],
            style=z.TextStyle(color=world.themes.theme.gray[100], scale=2.5),
            focus_parent=context['focus_parent'])
        sub_color = world.themes.theme.gray[400]
        sub_style = z.TextStyle(color=sub_color)
        self.info_text = z.Text(f'{item["score"]} points by', style=sub_style)
        self.author_link = z.Link(item['by'],
                                          foreground_color=sub_color,
                                          focus_parent=context['focus_parent'])
        self.time_text = z.Text(util.time_ago(item['time']),
                                        style=sub_style)
        self.comments_link = z.Link(f'{item.get("descendants", 0)} comments',
                                            foreground_color=sub_color,
                                          focus_parent=context['focus_parent'])
        self.row = z.Flex([
            z.FlexChild(self.info_text.layout),
            z.FlexChild(self.author_link.layout),
            z.FlexChild(self.time_text.layout),
            z.FlexChild(self.comments_link.layout),
        ])
        self.column = z.Flex([
            z.FlexChild(self.story_link.layout),
            z.FlexChild(self.row.layout)
        ], axis='y')
        self.padding = z.Padding(self.column.layout)
        self.layout = self.padding.layout
        
    def drop(self):
        self.padding.drop()
        self.column.drop()
        self.story_link.drop()
        self.row.drop()
        self.info_text.drop()
        self.author_link.drop()
        self.time_text.drop()
        self.comments_link.drop()

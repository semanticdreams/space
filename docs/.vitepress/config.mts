import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: "space",
  description: "space documentation",
  srcExclude: [
    'dev/openai/**',
    'dev/zai/**',
    'dev/fennel/**'
  ],
  head: [
    ['link', { rel: 'icon', href: '/space.png' }]
  ],
  themeConfig: {
    logo: '/space.png',
    // https://vitepress.dev/reference/default-theme-config
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Quick Start', link: '/user/quick-start' },
      { text: 'User', link: '/user/' },
      { text: 'Developer', link: '/dev/' }
    ],

    sidebar: {
      '/user/': [
        {
          text: 'User',
          items: [
            { text: 'Overview', link: '/user/' },
            { text: 'Quick Start', link: '/user/quick-start' }
          ]
        }
      ],
      '/dev/': [
        {
          text: 'Developer',
          items: [
            { text: 'Overview', link: '/dev/' }
          ]
        }
      ]
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/semanticdreams/space' }
    ]
  }
})

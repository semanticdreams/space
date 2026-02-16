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
            { text: 'Overview', link: '/dev/' },
            { text: 'Concepts', link: '/dev/concepts' },
            { text: 'Devlog', link: '/dev/devlog' }
          ]
        },
        {
          text: 'Architecture',
          items: [
            { text: 'aubio', link: '/dev/architecture/aubio' },
            { text: 'audio', link: '/dev/architecture/audio' },
            { text: 'directional-focus-traversal', link: '/dev/architecture/directional-focus-traversal' },
            { text: 'focus-change-ordering', link: '/dev/architecture/focus-change-ordering' },
            { text: 'force-layout-barnes-hut', link: '/dev/architecture/force-layout-barnes-hut' },
            { text: 'gltf-async-embedded-texture-decode', link: '/dev/architecture/gltf-async-embedded-texture-decode' },
            { text: 'graph-key-based-loaders', link: '/dev/architecture/graph-key-based-loaders' },
            { text: 'graph-llm', link: '/dev/architecture/graph-llm' },
            { text: 'graph-view-as-widget', link: '/dev/architecture/graph-view-as-widget' },
            { text: 'graph-vs-entities', link: '/dev/architecture/graph-vs-entities' },
            { text: 'graph', link: '/dev/architecture/graph' },
            { text: 'hackernews', link: '/dev/architecture/hackernews' },
            { text: 'icons', link: '/dev/architecture/icons' },
            { text: 'interpreter', link: '/dev/architecture/interpreter' },
            { text: 'layered-points-in-graph', link: '/dev/architecture/layered-points-in-graph' },
            { text: 'lighting', link: '/dev/architecture/lighting' },
            { text: 'link-entities', link: '/dev/architecture/link-entities' },
            { text: 'list-entities', link: '/dev/architecture/list-entities' },
            { text: 'loop', link: '/dev/architecture/loop' },
            { text: 'matrix', link: '/dev/architecture/matrix' },
            { text: 'multithreading', link: '/dev/architecture/multithreading' },
            { text: 'mystery-layout-error', link: '/dev/architecture/mystery-layout-error' },
            { text: 'preload', link: '/dev/architecture/preload' },
            { text: 'process', link: '/dev/architecture/process' },
            { text: 'prof-graph-layout', link: '/dev/architecture/prof-graph-layout' },
            { text: 'prof-scroll', link: '/dev/architecture/prof-scroll' },
            { text: 'prof-terminal', link: '/dev/architecture/prof-terminal' },
            { text: 'render-architecture', link: '/dev/architecture/render-architecture' },
            { text: 'render-capture', link: '/dev/architecture/render-capture' },
            { text: 'resize-bugs', link: '/dev/architecture/resize-bugs' },
            { text: 'selection', link: '/dev/architecture/selection' },
            { text: 'string-entities', link: '/dev/architecture/string-entities' },
            { text: 'sub-app', link: '/dev/architecture/sub-app' },
            { text: 'sub_world', link: '/dev/architecture/sub_world' },
            { text: 'tempfile', link: '/dev/architecture/tempfile' },
            { text: 'terminal', link: '/dev/architecture/terminal' },
            { text: 'testing-http-clients', link: '/dev/architecture/testing-http-clients' },
            { text: 'transform-pass', link: '/dev/architecture/transform-pass' },
            { text: 'wallet-core', link: '/dev/architecture/wallet-core' },
            { text: 'wallet', link: '/dev/architecture/wallet' },
            { text: 'wlroots-status', link: '/dev/architecture/wlroots-status' },
            { text: 'xapian', link: '/dev/architecture/xapian' },
            { text: 'xdg-icon-browser-and-svg-support', link: '/dev/architecture/xdg-icon-browser-and-svg-support' }
          ]
        }
      ]
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/semanticdreams/space' }
    ],

    footer: {
      message: "Join the community on <a href='https://matrix.to/#/#spaceui.org:matrix.org' target='_blank'>Matrix</a>."
    }
  }
})

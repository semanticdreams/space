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
    search: {
      provider: 'local'
    },
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
      { icon: 'github', link: 'https://github.com/semanticdreams/space' },
      {
        icon: {
          svg: `<svg width="32" height="32" viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
   <path fill="currentColor" d="M 30,2.0000001 V 30 h -1 -2 v 2 h 5 V -3.3333334e-8 L 27,0 v 2 z"/>
   <path fill="currentColor" d="M 9.9515939,10.594002 V 12.138 h 0.043994 c 0.3845141,-0.563728 0.8932271,-1.031728 1.4869981,-1.368 0.580003,-0.322998 1.244999,-0.485 1.993002,-0.485 0.72,0 1.376999,0.139993 1.971998,0.42 0.595,0.279004 1.047001,0.771001 1.355002,1.477001 0.338003,-0.500001 0.795999,-0.941 1.376999,-1.323001 0.579999,-0.382998 1.265998,-0.574 2.059998,-0.574 0.602003,0 1.160002,0.074 1.674002,0.220006 0.514,0.148006 0.953998,0.382998 1.321999,0.706998 0.36601,0.322999 0.653001,0.746 0.859,1.268002 0.205001,0.521998 0.307994,1.15 0.307994,1.887001 v 7.632997 h -3.127 v -6.463997 c 0,-0.383002 -0.01512,-0.743002 -0.04399,-1.082003 -0.02079,-0.3072 -0.103219,-0.607113 -0.242003,-0.881998 -0.133153,-0.25081 -0.335962,-0.457777 -0.584001,-0.596002 -0.257008,-0.146003 -0.605998,-0.220006 -1.046997,-0.220006 -0.440002,0 -0.796003,0.085 -1.068,0.253002 -0.272013,0.170003 -0.485001,0.390002 -0.639001,0.662003 -0.159119,0.287282 -0.263585,0.601602 -0.307994,0.926997 -0.05197,0.346923 -0.07801,0.697217 -0.07801,1.048002 v 6.353999 h -3.128005 v -6.398 c 0,-0.338003 -0.0072,-0.673001 -0.02116,-1.004001 -0.01134,-0.313663 -0.07487,-0.623229 -0.187994,-0.915999 -0.107943,-0.276623 -0.300435,-0.512126 -0.550001,-0.673001 -0.25799,-0.168 -0.636,-0.253002 -1.134999,-0.253002 -0.198123,0.0083 -0.394383,0.04195 -0.584002,0.100006 -0.258368,0.07446 -0.498455,0.201827 -0.704999,0.373985 -0.227981,0.183987 -0.421999,0.449 -0.583997,0.794003 -0.161008,0.345978 -0.242003,0.797998 -0.242003,1.356998 v 6.618999 H 6.99942 V 10.590001 Z"/>
   <path fill="currentColor" d="M 2,2.0000001 V 30 h 3 v 2 H 0 V 9.2650922e-8 L 5,0 v 2 z"/>
</svg>`
        },
        link: 'https://matrix.to/#/#spaceui.org:matrix.org',
        ariaLabel: 'matrix'
      }
    ],

    footer: {
      message: "Join the community on <a href='https://matrix.to/#/#spaceui.org:matrix.org' target='_blank'>Matrix</a>."
    }
  }
})

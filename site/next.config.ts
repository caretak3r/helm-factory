import nextra from 'nextra'
import remarkMermaidTheme from './remark-mermaid-theme.mjs'

const withNextra = nextra({
  latex: true,                       // KaTeX — $inline$ and $$display$$ math
  defaultShowCopyCode: true,
  search: { codeblocks: false },
  contentDirBasePath: '/',
  mdxOptions: {
    remarkPlugins: [remarkMermaidTheme] // Okabe-Ito palette on every diagram
  }
})

export default withNextra({
  reactStrictMode: true,
  output: 'export',
  images: { unoptimized: true },
  trailingSlash: true,
  // Repo is PUBLIC, served at https://caretak3r.github.io/helm-factory/
  // (public-project Pages row: basePath: '/<repo>')
  basePath: '/helm-factory'
})

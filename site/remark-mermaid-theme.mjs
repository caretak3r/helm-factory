/**
 * remark-mermaid-theme — inject a colorblind-safe Okabe-Ito theme into every
 * mermaid fence at build time.
 *
 * Register BEFORE Nextra's own pipeline touches the tree (nextra() merges
 * mdxOptions.remarkPlugins ahead of its internals):
 *
 *   import remarkMermaidTheme from './remark-mermaid-theme.mjs'
 *   const withNextra = nextra({ mdxOptions: { remarkPlugins: [remarkMermaidTheme] }, ... })
 *
 * Why an init directive and not CSS: mermaid inlines nearly all styling into
 * the emitted SVG, so stylesheet overrides are brittle and version-fragile.
 * The `%%{init}%%` directive is mermaid's supported per-diagram theming
 * channel; injecting it at build time makes it site-wide with zero authoring
 * boilerplate. A fence that already carries its own `%%{init` is left
 * untouched — explicit author intent wins.
 *
 * Palette: Okabe & Ito (2008), the standard colorblind-safe 8-color set —
 * distinguishable under deuteranopia, protanopia, and tritanopia. Text on
 * fills is pinned near-black (WCAG AA on every fill); lines are mid-gray so
 * they stay visible on light AND dark page backgrounds (theme "base" renders
 * the same in both modes — fixed colors are the price of a guaranteed
 * palette, and mid-tone fills with dark text read fine on either).
 */

const OKABE_ITO = {
  theme: 'base',
  themeVariables: {
    // node fills, cycled by mermaid across classes/subgraphs
    primaryColor: '#56B4E9',       // sky blue
    secondaryColor: '#E69F00',     // orange
    tertiaryColor: '#CC79A7',      // reddish purple
    primaryTextColor: '#111111',
    secondaryTextColor: '#111111',
    tertiaryTextColor: '#111111',
    primaryBorderColor: '#0072B2', // blue
    secondaryBorderColor: '#D55E00', // vermillion
    tertiaryBorderColor: '#009E73',  // bluish green
    lineColor: '#7f7f7f',
    textColor: '#7f7f7f',          // edge labels sit on page bg: mid-gray for both modes
    edgeLabelBackground: 'transparent',
    clusterBkg: 'transparent',
    clusterBorder: '#7f7f7f',
    // pie / xychart series in Okabe-Ito order
    pie1: '#0072B2', pie2: '#E69F00', pie3: '#009E73', pie4: '#CC79A7',
    pie5: '#56B4E9', pie6: '#D55E00', pie7: '#F0E442', pie8: '#999999',
    pieTitleTextColor: '#7f7f7f',
    pieSectionTextColor: '#111111',
    pieLegendTextColor: '#7f7f7f'
  }
}

const DIRECTIVE = `%%{init: ${JSON.stringify(OKABE_ITO)}}%%\n`

export default function remarkMermaidTheme() {
  return tree => {
    visitCode(tree, node => {
      if (node.lang !== 'mermaid') return
      if (typeof node.value !== 'string') return
      if (node.value.includes('%%{init')) return // author override wins
      node.value = DIRECTIVE + node.value
    })
  }
}

// Minimal depth-first walk over code nodes — avoids a unist-util-visit dep.
function visitCode(node, fn) {
  if (node.type === 'code') fn(node)
  const children = node.children
  if (Array.isArray(children)) for (const child of children) visitCode(child, fn)
}

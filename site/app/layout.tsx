import type { ReactNode } from 'react'
import { Footer, Layout, Navbar } from 'nextra-theme-docs'
import { Head } from 'nextra/components'
import { getPageMap } from 'nextra/page-map'
import 'nextra-theme-docs/style.css'
import 'katex/dist/katex.min.css'
import DiagramZoom from './diagram-zoom'

export const metadata = {
  title: { default: 'platform', template: '%s – platform' },
  description: 'A Helm 4 pure library chart for hardened, capability-negotiated Kubernetes manifests.'
}

const navbar = <Navbar logo={<b>platform</b>} />
const footer = <Footer>MIT {new Date().getFullYear()} © caretak3r/helm-factory</Footer>

export default async function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" dir="ltr" suppressHydrationWarning>
      <Head />
      <body>
        <Layout navbar={navbar} pageMap={await getPageMap()} footer={footer}>
          {children}
        </Layout>
        <DiagramZoom />
      </body>
    </html>
  )
}

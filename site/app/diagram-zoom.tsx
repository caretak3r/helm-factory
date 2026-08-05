'use client'

/**
 * DiagramZoom — click-to-enlarge for mermaid diagrams. Dep-free.
 *
 * Mount ONCE in the root layout (inside <body>). It event-delegates on the
 * document, so it enlarges any mermaid SVG regardless of how it was rendered
 * (Nextra's built-in pipeline, @theguild/remark-mermaid, or hand-mounted).
 * Hook: mermaid's auto-generated svg ids start with "mermaid" — but a
 * custom renderer using React useId does NOT (ids look like _R_..._), so
 * the selector also matches any svg inside a figure.diagram plate. Custom
 * renderers must either sit in figure.diagram or prefix render ids with
 * "mermaid".
 *
 * Interactions: click diagram → full-screen native <dialog>; wheel or +/−
 * buttons to zoom; drag to pan; ⌂ resets; Esc or backdrop click closes.
 * Accessibility: dialog is labeled, controls are real buttons, transitions
 * are dropped under prefers-reduced-motion, and the trigger affordance is a
 * zoom-in cursor (the inline diagram stays fully readable without ever
 * opening the dialog — zoom is enhancement, not requirement).
 */

import { useCallback, useEffect, useRef, useState } from 'react'

const SVG_SELECTOR = 'svg[id^="mermaid"], figure.diagram svg'
const SCALE_MIN = 0.4
const SCALE_MAX = 8
const SCALE_STEP = 1.25

export default function DiagramZoom() {
  const dialogRef = useRef<HTMLDialogElement>(null)
  const hostRef = useRef<HTMLDivElement>(null)
  const [scale, setScale] = useState(1)
  const [tx, setTx] = useState(0)
  const [ty, setTy] = useState(0)
  const drag = useRef<{ x: number; y: number; tx: number; ty: number } | null>(null)

  const reset = useCallback(() => {
    setScale(1)
    setTx(0)
    setTy(0)
  }, [])

  const close = useCallback(() => {
    dialogRef.current?.close()
    if (hostRef.current) hostRef.current.innerHTML = ''
    reset()
  }, [reset])

  useEffect(() => {
    const style = document.createElement('style')
    style.textContent = `${SVG_SELECTOR} { cursor: zoom-in; }`
    document.head.appendChild(style)

    const onClick = (e: MouseEvent) => {
      const svg = (e.target as Element | null)?.closest?.(SVG_SELECTOR)
      if (!svg || !dialogRef.current || !hostRef.current) return
      if (dialogRef.current.open) return
      // Mermaid scopes its embedded <style> AND marker/clip url(#…) refs
      // to the svg id. Stripping the id orphans the stylesheet (edges
      // render as filled black blobs); keeping it duplicates ids. So:
      // serialize and remap the id token everywhere — styles, defs, refs.
      const uid = `zoomed-${Date.now()}`
      const html = svg.id
        ? svg.outerHTML.replaceAll(svg.id, uid)
        : svg.outerHTML
      hostRef.current.innerHTML = html
      const inserted = hostRef.current.querySelector('svg')
      if (inserted) {
        inserted.style.cursor = 'default'
        inserted.style.maxWidth = 'none'
        inserted.style.width = '100%'
        inserted.style.height = 'auto'
      }
      dialogRef.current.showModal()
    }
    document.addEventListener('click', onClick)
    return () => {
      document.removeEventListener('click', onClick)
      style.remove()
    }
  }, [])

  const onWheel = (e: React.WheelEvent) => {
    e.preventDefault()
    const factor = e.deltaY < 0 ? SCALE_STEP : 1 / SCALE_STEP
    setScale(s => Math.min(SCALE_MAX, Math.max(SCALE_MIN, s * factor)))
  }

  const onPointerDown = (e: React.PointerEvent) => {
    ;(e.target as Element).setPointerCapture?.(e.pointerId)
    drag.current = { x: e.clientX, y: e.clientY, tx, ty }
  }
  const onPointerMove = (e: React.PointerEvent) => {
    if (!drag.current) return
    setTx(drag.current.tx + (e.clientX - drag.current.x))
    setTy(drag.current.ty + (e.clientY - drag.current.y))
  }
  const onPointerUp = () => {
    drag.current = null
  }

  const zoom = (dir: 1 | -1) =>
    setScale(s => Math.min(SCALE_MAX, Math.max(SCALE_MIN, dir > 0 ? s * SCALE_STEP : s / SCALE_STEP)))

  const btn: React.CSSProperties = {
    font: '16px/1 system-ui, sans-serif',
    minWidth: 36,
    height: 36,
    border: '1px solid #7f7f7f',
    borderRadius: 6,
    background: 'Canvas',
    color: 'CanvasText',
    cursor: 'pointer'
  }

  return (
    <dialog
      ref={dialogRef}
      aria-label="Enlarged diagram"
      onClick={e => {
        if (e.target === dialogRef.current) close() // backdrop click
      }}
      onClose={() => {
        if (hostRef.current) hostRef.current.innerHTML = ''
        reset()
      }}
      style={{
        width: '96vw',
        height: '94vh',
        maxWidth: 'none',
        maxHeight: 'none',
        padding: 0,
        border: 'none',
        borderRadius: 8,
        overflow: 'hidden',
        background: 'Canvas',
        color: 'CanvasText'
      }}
    >
      <div
        role="toolbar"
        aria-label="Diagram zoom controls"
        style={{
          position: 'absolute',
          top: 10,
          right: 12,
          zIndex: 2,
          display: 'flex',
          gap: 6
        }}
      >
        <button type="button" style={btn} aria-label="Zoom in" onClick={() => zoom(1)}>+</button>
        <button type="button" style={btn} aria-label="Zoom out" onClick={() => zoom(-1)}>−</button>
        <button type="button" style={btn} aria-label="Reset view" onClick={reset}>⌂</button>
        <button type="button" style={btn} aria-label="Close" onClick={close}>✕</button>
      </div>
      <div
        onWheel={onWheel}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        style={{
          width: '100%',
          height: '100%',
          overflow: 'hidden',
          cursor: drag.current ? 'grabbing' : 'grab',
          touchAction: 'none',
          display: 'grid',
          placeItems: 'center'
        }}
      >
        <div
          ref={hostRef}
          style={{
            transform: `translate(${tx}px, ${ty}px) scale(${scale})`,
            transition:
              typeof window !== 'undefined' &&
              window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
                ? 'none'
                : 'transform 80ms linear',
            width: 'min(92vw, 1400px)'
          }}
        />
      </div>
    </dialog>
  )
}

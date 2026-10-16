import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useThreads } from '../hooks/ThreadsContext'
import ThreadDetails from './ThreadDetails'
import ThreadTile from './ThreadTile'
import UploadTile from './UploadTile'

// Tile geometry, matching ThreadTile (128px) and the grid's gap-1 / p-1.
const TILE = 128
const GAP = 4
const PAD = 4

export default function ThreadList() {
  // Loaded once in ThreadsProvider, so the thread page can page through the
  // same list. Expired posts hide their own tiles; `expired` is only so the
  // page can say so, because a grid that silently shrinks reads as a bug in
  // the app rather than as content that stopped being paid for.
  const { ids: allThreadIds, allLoaded, error: totalThreadsError, expired, reportStatus: handleTileStatus } = useThreads()

  // /threads/:id opens that post inline, below the row of its thumbnail, with
  // the rest of the grid continuing underneath — the way pr0 does it.
  const { threadId: selected } = useParams<{ threadId: string }>()
  const navigate = useNavigate()
  const close = useCallback(() => navigate('/'), [navigate])

  // Columns follow the width, so the panel lands after the right row on any
  // screen. flex-wrap packs as many 128px tiles as fit.
  const gridRef = useRef<HTMLDivElement>(null)
  const [cols, setCols] = useState(1)
  useLayoutEffect(() => {
    const el = gridRef.current
    if (!el) return
    const measure = () => setCols(Math.max(1, Math.floor((el.clientWidth - 2 * PAD + GAP) / (TILE + GAP))))
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])
  const rowWidth = cols * TILE + (cols - 1) * GAP

  // Expired tiles render nothing, so leave them out of the count, or the
  // panel would land in the wrong row. The open post stays even if expired.
  const visible = allThreadIds.filter(id => id === selected || !expired.has(id))
  // +1: the upload tile is the first cell of the grid.
  const cell = selected ? visible.indexOf(selected) + 1 : 0
  const found = cell > 0
  // Index (in visible) of the last thread in the selected tile's row. Until
  // the list reaches a deep-linked post, the panel waits at the top.
  const rowEnd = found ? Math.min(visible.length + 1, Math.ceil((cell + 1) / cols) * cols) - 2 : -1

  // Bring the opened post to the top of the screen (under the sticky nav)
  // when it opens or when paging moves it to another row.
  const panelRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (selected) panelRef.current?.scrollIntoView({ block: 'start' })
  }, [selected, found])

  const panel = selected && (
    <div ref={panelRef} key={`panel-${selected}`} className="w-full flex justify-center scroll-mt-[56px] my-1">
      <div className="max-w-full" style={{ width: rowWidth }}>
        <ThreadDetails threadId={selected} onClose={close} />
      </div>
    </div>
  )

  if (totalThreadsError) {
    return (
      <p className="text-center text-[#888] mt-20 text-sm">
        Could not reach the contract. Check your network connection and reload.
      </p>
    )
  }

  return (
    <div ref={gridRef} className="flex flex-wrap gap-1 p-1 justify-center">
      {!found && panel}
      <UploadTile />
      {visible.map((threadId, i) => [
        <ThreadTile threadId={threadId} key={threadId} onStatus={handleTileStatus} selected={threadId === selected} />,
        found && i === rowEnd ? panel : null,
      ])}
      {!allLoaded && (
        <div className="w-[128px] h-[128px] bg-[#212121] animate-pulse" />
      )}
      {allLoaded && expired.size > 0 && (
        <p className="w-full text-center text-xs text-[#666] py-6">
          {expired.size === allThreadIds.length
            ? 'Every post here has expired from Swarm — their postage stamps ran out and the network dropped the images. Post something to start it off again.'
            : `${expired.size} ${expired.size === 1 ? 'post is' : 'posts are'} hidden: their postage stamps expired and the images are no longer on Swarm.`}
        </p>
      )}
    </div>
  )
}

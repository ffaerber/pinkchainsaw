import { useEffect } from 'react'
import { useReadContract } from 'wagmi'
import { Link } from 'react-router'
import { PINKCHAINSAW_ABI, PINKCHAINSAW_ADDRESS } from '../config/contracts'
import { useBeeContext } from '../hooks/BeeContext'
import { useBzzStatus } from '../hooks/useBzzStatus'
import SwarmImage from './SwarmImage'

interface ThreadTileProps {
  threadId: string
  /** Called once the tile knows whether its image is still on Swarm, so the
      grid can say how many posts it is hiding instead of silently shrinking. */
  onStatus?: (threadId: string, alive: boolean) => void
  /** This post is open below its row; clicking the tile again closes it. */
  selected?: boolean
}

export default function ThreadTile({ threadId, onStatus, selected = false }: ThreadTileProps) {
  const { read } = useBeeContext()
  const { data: thread } = useReadContract({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    functionName: 'getThread',
    args: [threadId as `0x${string}`],
  })

  const post = thread as any
  const bzzhash = post ? (post.bzzhash as string).replace('0x', '') : undefined
  const status = useBzzStatus(read, bzzhash)

  useEffect(() => {
    if (status === 'checking') return
    onStatus?.(threadId, status === 'alive')
  }, [status, threadId, onStatus])

  if (!thread) return <div className="w-[128px] h-[128px] bg-[#212121] animate-pulse" />

  // The stamp that paid for this image has expired: the chunks are gone and the
  // gateway has nothing to serve. Drop the tile rather than leave a broken
  // image in the grid — the thread itself still exists and is still reachable
  // by its own URL.
  if (status === 'dead') return null
  if (status === 'checking') return <div className="w-[128px] h-[128px] bg-[#212121] animate-pulse" />

  return (
    <Link
      to={selected ? '/' : `/threads/${threadId}`}
      className={`block w-[128px] h-[128px] bg-[#212121] overflow-hidden ${selected ? 'outline outline-2 -outline-offset-2 outline-[#e84393]' : ''}`}
    >
      <SwarmImage
        path={`/bzz/${bzzhash}`}
        lazy
        className="w-full h-full object-cover hover:opacity-80 transition-opacity"
        placeholderClassName="w-full h-full"
      />
    </Link>
  )
}

import { useEffect } from 'react'
import { useReadContract } from 'wagmi'
import { Link } from 'react-router'
import { PINKCHAINSAW_ABI, PINKCHAINSAW_ADDRESS } from '../config/contracts'
import { useBeeContext } from '../hooks/BeeContext'
import { useBzzStatus } from '../hooks/useBzzStatus'

interface ThreadTileProps {
  threadId: string
  /** Called once the tile knows whether its image is still on Swarm, so the
      grid can say how many posts it is hiding instead of silently shrinking. */
  onStatus?: (threadId: string, alive: boolean) => void
}

export default function ThreadTile({ threadId, onStatus }: ThreadTileProps) {
  const { readUrl } = useBeeContext()
  const { data: thread } = useReadContract({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    functionName: 'getThread',
    args: [threadId as `0x${string}`],
  })

  const post = thread as any
  const bzzhash = post ? (post.bzzhash as string).replace('0x', '') : undefined
  const status = useBzzStatus(readUrl, bzzhash)

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

  const imgSrc = `${readUrl}/bzz/${bzzhash}`

  return (
    <Link to={`/threads/${threadId}`} className="block w-[128px] h-[128px] bg-[#212121] overflow-hidden">
      <img src={imgSrc} className="w-full h-full object-cover hover:opacity-80 transition-opacity" alt="" loading="lazy" />
    </Link>
  )
}

import { useReadContract } from 'wagmi'
import { Link } from 'react-router'
import { PINKCHAINSAW_ABI, PINKCHAINSAW_ADDRESS } from '../config/contracts'
import { useBeeContext } from '../hooks/BeeContext'

interface ThreadTileProps {
  threadId: string
}

export default function ThreadTile({ threadId }: ThreadTileProps) {
  const { readUrl } = useBeeContext()
  const { data: thread } = useReadContract({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    functionName: 'getThread',
    args: [threadId as `0x${string}`],
  })

  if (!thread) return <div className="w-[128px] h-[128px] bg-[#212121] animate-pulse" />

  const post = thread as any
  const bzzhash = (post.bzzhash as string).replace('0x', '')
  const imgSrc = `${readUrl}/bzz/${bzzhash}`

  return (
    <Link to={`/threads/${threadId}`} className="block w-[128px] h-[128px] bg-[#212121] overflow-hidden">
      <img src={imgSrc} className="w-full h-full object-cover hover:opacity-80 transition-opacity" alt="" loading="lazy" />
    </Link>
  )
}

import { useCallback, useEffect, useState } from 'react'
import { useReadContract, useWatchContractEvent } from 'wagmi'
import { PINKCHAINSAW_ABI, PINKCHAINSAW_ADDRESS } from '../config/contracts'
import ThreadTile from './ThreadTile'
import UploadTile from './UploadTile'
import { zeroHash } from 'viem'

export default function ThreadList() {
  const [allThreadIds, setAllThreadIds] = useState<string[]>([])
  const [currentPage, setCurrentPage] = useState<number | null>(null)
  const [allLoaded, setAllLoaded] = useState(false)
  const hashesPerPage = 20

  const { data: totalThreads, error: totalThreadsError } = useReadContract({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    functionName: 'getTotalThreads',
  })

  useEffect(() => {
    if (totalThreads === undefined) return
    const total = Number(totalThreads)
    if (total === 0) { setAllLoaded(true); return }
    const totalPages = Math.ceil(total / hashesPerPage)
    if (currentPage === null) setCurrentPage(totalPages)
  }, [totalThreads, currentPage])

  const { data: pageThreadIds } = useReadContract({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    functionName: 'getPaginatedThreadIds',
    args: currentPage ? [BigInt(currentPage), BigInt(hashesPerPage)] : undefined,
    query: { enabled: currentPage !== null && currentPage >= 1 },
  })

  useEffect(() => {
    if (!pageThreadIds) return
    const ids = (pageThreadIds as string[]).filter(id => id !== zeroHash).reverse()
    setAllThreadIds(prev => {
      const existing = new Set(prev)
      const newIds = ids.filter(id => !existing.has(id))
      return newIds.length > 0 ? [...prev, ...newIds] : prev
    })
    if (currentPage !== null && currentPage > 1) {
      setCurrentPage(currentPage - 1)
    } else {
      setAllLoaded(true)
    }
  }, [pageThreadIds])

  useWatchContractEvent({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    eventName: 'ThreadCreated',
    onLogs(logs) {
      for (const log of logs) {
        // the event carries the post id, not the swarm hash
        const id = (log as any).args?.id as string
        if (id) {
          setAllThreadIds(prev => prev.includes(id) ? prev : [id, ...prev])
        }
      }
    },
  })

  // Posts whose image has expired from Swarm. The tiles hide themselves; this is
  // only so the page can say so, because a grid that silently shrinks reads as a
  // bug in the app rather than as content that stopped being paid for.
  const [expired, setExpired] = useState<Set<string>>(new Set())
  const handleTileStatus = useCallback((threadId: string, alive: boolean) => {
    setExpired(prev => {
      const has = prev.has(threadId)
      if (alive === !has) return prev
      const next = new Set(prev)
      if (alive) next.delete(threadId)
      else next.add(threadId)
      return next
    })
  }, [])

  if (totalThreadsError) {
    return (
      <p className="text-center text-[#888] mt-20 text-sm">
        Could not reach the contract. Check your network connection and reload.
      </p>
    )
  }

  return (
    <div className="flex flex-wrap gap-1 p-1 justify-center">
      <UploadTile />
      {allThreadIds.map(threadId => (
        <ThreadTile threadId={threadId} key={threadId} onStatus={handleTileStatus} />
      ))}
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

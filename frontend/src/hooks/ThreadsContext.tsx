import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { useReadContract, useWatchContractEvent } from 'wagmi'
import { zeroHash } from 'viem'
import { PINKCHAINSAW_ABI, PINKCHAINSAW_ADDRESS } from '../config/contracts'

/**
 * The list of every thread id, newest first, loaded once for the whole app.
 *
 * It lives above the routes rather than in the grid so the thread page can
 * page through the same order with its arrows — including when it was opened
 * from a link and the grid never mounted. The contract has no "position of
 * thread X" lookup, so the list is the only way to know a thread's neighbours.
 */
interface ThreadsState {
  /** Thread ids, newest first (the grid's order). */
  ids: string[]
  allLoaded: boolean
  error: unknown
  /** Threads whose image has expired from Swarm; the grid hides them. */
  expired: Set<string>
  reportStatus: (threadId: string, alive: boolean) => void
}

const ThreadsContext = createContext<ThreadsState | null>(null)

const HASHES_PER_PAGE = 20

export function ThreadsProvider({ children }: { children: ReactNode }) {
  const [ids, setIds] = useState<string[]>([])
  const [currentPage, setCurrentPage] = useState<number | null>(null)
  const [allLoaded, setAllLoaded] = useState(false)

  const { data: totalThreads, error } = useReadContract({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    functionName: 'getTotalThreads',
  })

  // Pages are 1-based and oldest first; start at the last page (the newest
  // threads) and walk back, so the first screen fills quickly.
  useEffect(() => {
    if (totalThreads === undefined) return
    const total = Number(totalThreads)
    if (total === 0) { setAllLoaded(true); return }
    const totalPages = Math.ceil(total / HASHES_PER_PAGE)
    if (currentPage === null) setCurrentPage(totalPages)
  }, [totalThreads, currentPage])

  const { data: pageThreadIds } = useReadContract({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    functionName: 'getPaginatedThreadIds',
    args: currentPage ? [BigInt(currentPage), BigInt(HASHES_PER_PAGE)] : undefined,
    query: { enabled: currentPage !== null && currentPage >= 1 },
  })

  useEffect(() => {
    if (!pageThreadIds) return
    const page = (pageThreadIds as string[]).filter(id => id !== zeroHash).reverse()
    setIds(prev => {
      const existing = new Set(prev)
      const newIds = page.filter(id => !existing.has(id))
      return newIds.length > 0 ? [...prev, ...newIds] : prev
    })
    if (currentPage !== null && currentPage > 1) {
      setCurrentPage(currentPage - 1)
    } else {
      setAllLoaded(true)
    }
  }, [pageThreadIds])

  useWatchContractEvent({
    // Poll with eth_getLogs instead of eth_newFilter: the public Gnosis RPC
    // rejects filter creation with a 400, which surfaced as a console full of
    // failed POSTs to rpc.gnosischain.com on every mount.
    poll: true,
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    eventName: 'ThreadCreated',
    onLogs(logs) {
      for (const log of logs) {
        // the event carries the post id, not the swarm hash
        const id = (log as any).args?.id as string
        if (id) setIds(prev => prev.includes(id) ? prev : [id, ...prev])
      }
    },
  })

  const [expired, setExpired] = useState<Set<string>>(new Set())
  const reportStatus = useCallback((threadId: string, alive: boolean) => {
    setExpired(prev => {
      const has = prev.has(threadId)
      if (alive === !has) return prev
      const next = new Set(prev)
      if (alive) next.delete(threadId)
      else next.add(threadId)
      return next
    })
  }, [])

  const value = useMemo(
    () => ({ ids, allLoaded, error, expired, reportStatus }),
    [ids, allLoaded, error, expired, reportStatus],
  )
  return <ThreadsContext.Provider value={value}>{children}</ThreadsContext.Provider>
}

export function useThreads() {
  const ctx = useContext(ThreadsContext)
  if (!ctx) throw new Error('useThreads must be used within ThreadsProvider')
  return ctx
}

/**
 * The neighbours of a thread in the grid's order, skipping threads whose image
 * is known to have expired (the grid hides those too). `newer` is the one to
 * its left in the grid, `older` the one to its right; undefined at either end
 * or while the list has not reached this thread yet.
 */
export function useThreadNeighbours(threadId: string | undefined) {
  const { ids, expired } = useThreads()
  return useMemo(() => {
    const visible = ids.filter(id => id === threadId || !expired.has(id))
    const i = threadId ? visible.indexOf(threadId) : -1
    if (i < 0) return { newer: undefined, older: undefined }
    return { newer: visible[i - 1], older: visible[i + 1] }
  }, [ids, expired, threadId])
}

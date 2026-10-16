import { useEffect, useRef, useState } from 'react'
import { RETRIES, retryDelayMs } from '../lib/retry'
import Spinner from './Spinner'

/**
 * An <img> for Swarm content that survives a slow gateway.
 *
 * useBzzStatus only proves the first chunk is retrievable. The rest of the
 * image is fetched chunk by chunk from the network, and a gateway that cannot
 * get one of them in time answers 404/5xx or simply hangs — a plain <img> then
 * shows a broken icon and never asks again. So the bytes are fetched here with
 * a timeout and retried with backoff, and the <img> only ever sees a finished
 * blob. Retries are worth it: the second attempt usually finds the chunks
 * cached on the gateway node that fetched them the first time.
 */

const ATTEMPT_TIMEOUT_MS = 30_000

type Phase = 'waiting' | 'loading' | 'loaded' | 'failed'

interface SwarmImageProps {
  src: string
  alt?: string
  /** Classes for the <img> once it has loaded. */
  className?: string
  /** Classes for the box shown while loading or after giving up. */
  placeholderClassName?: string
  /** Start fetching only when near the viewport (grid tiles). */
  lazy?: boolean
}

export default function SwarmImage({ src, alt = '', className, placeholderClassName, lazy }: SwarmImageProps) {
  const boxRef = useRef<HTMLDivElement>(null)
  const [visible, setVisible] = useState(!lazy)
  const [phase, setPhase] = useState<Phase>('waiting')
  const [attempt, setAttempt] = useState(0)
  // Bumped by "tap to retry", so a manual retry reruns even when attempt is 0.
  const [round, setRound] = useState(0)
  const [blobUrl, setBlobUrl] = useState<string>()

  useEffect(() => {
    if (visible || !boxRef.current) return
    const io = new IntersectionObserver(entries => {
      if (entries.some(e => e.isIntersecting)) setVisible(true)
    }, { rootMargin: '200px' })
    io.observe(boxRef.current)
    return () => io.disconnect()
  }, [visible])

  // A new reference starts over.
  useEffect(() => {
    setAttempt(0)
    setPhase('waiting')
  }, [src])

  useEffect(() => {
    if (!visible || !src) return
    let cancelled = false
    let url: string | undefined
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), ATTEMPT_TIMEOUT_MS)
    let retryTimer: ReturnType<typeof setTimeout> | undefined

    setPhase('loading')
    // A retry must not be answered from the HTTP cache that just failed it.
    fetch(src, { signal: controller.signal, cache: attempt > 0 || round > 0 ? 'reload' : 'default' })
      .then(res => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        return res.blob()
      })
      .then(blob => {
        if (cancelled) return
        url = URL.createObjectURL(blob)
        setBlobUrl(url)
        setPhase('loaded')
      })
      .catch(() => {
        if (cancelled) return
        if (attempt < RETRIES) {
          retryTimer = setTimeout(() => setAttempt(a => a + 1), retryDelayMs(attempt))
        } else {
          setPhase('failed')
        }
      })
      .finally(() => clearTimeout(timer))

    return () => {
      cancelled = true
      clearTimeout(timer)
      clearTimeout(retryTimer)
      controller.abort()
      if (url) URL.revokeObjectURL(url)
    }
  }, [visible, src, attempt, round])

  if (phase === 'loaded' && blobUrl) {
    return (
      <img
        src={blobUrl}
        alt={alt}
        className={className}
        // A blob that is not a decodable image counts as a failed attempt.
        onError={() => (attempt < RETRIES ? setAttempt(a => a + 1) : setPhase('failed'))}
      />
    )
  }

  const retryNow = (e: React.MouseEvent) => {
    // The tile wraps this in a <Link>; retrying must not navigate.
    e.preventDefault()
    e.stopPropagation()
    setAttempt(0)
    setRound(r => r + 1)
  }

  return (
    <div
      ref={boxRef}
      className={`flex flex-col items-center justify-center gap-2 bg-[#212121] text-[#666] ${placeholderClassName ?? ''}`}
    >
      {phase === 'failed' ? (
        <button
          type="button"
          onClick={retryNow}
          className="flex flex-col items-center gap-1 text-xs hover:text-[#e84393] transition-colors"
          title="The gateway did not deliver this image. Try again."
        >
          <svg viewBox="0 0 24 24" className="w-6 h-6" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M21 12a9 9 0 1 1-3-6.7L21 8" />
            <path d="M21 3v5h-5" />
          </svg>
          tap to retry
        </button>
      ) : (
        <>
          <Spinner className="w-6 h-6" />
          {attempt > 0 && <span className="text-[10px]">retry {attempt}/{RETRIES}</span>}
        </>
      )}
    </div>
  )
}

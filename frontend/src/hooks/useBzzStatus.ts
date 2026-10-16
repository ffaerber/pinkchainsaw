import { useEffect, useState } from 'react'

/**
 * Swarm content only stays retrievable while the postage batch that stamped it
 * is still paid for. When a poster's stamp expires their chunks stop being
 * served, but the reference stays in the contract forever — so "the thread
 * exists on chain" and "the image can still be fetched" are different facts,
 * and the UI has to ask the second question rather than assume it.
 *
 * Asked with a one-byte ranged GET instead of HEAD: gateways do not all
 * implement HEAD on /bzz, and a range costs a single byte of transfer. A
 * missing chunk can also hang rather than answer, since the gateway keeps
 * trying to retrieve it from the network before giving up, so the probe carries
 * its own timeout — a request that never resolves is, for a user staring at an
 * empty square, the same thing as a 404.
 *
 * Answers are cached per reference for the session. Content that has expired
 * does not come back (the chunks are gone once nobody pays for them), and a
 * live reference re-checks on the next page load, which is often enough. Only
 * a 404 counts as expired; a timeout or 5xx is no verdict, is not cached, and
 * reports 'alive' so the image loader (which retries) gets to try.
 */
export type BzzStatus = 'checking' | 'alive' | 'dead'

// Measured against both read paths before picking this: a Bee node gives up on
// an unpayable chunk after ~7s, api.gateway.ethswarm.org after ~14s. A timeout
// shorter than that aborts before the 404 arrives, so the answer never gets
// cached and every render pays the wait again.
const PROBE_TIMEOUT_MS = 20_000
// v2: v1 cached timeouts as dead, so drop those entries.
const CACHE_KEY = 'bzz-status-v2'

const cache: Map<string, 'alive' | 'dead'> = loadCache()

function loadCache(): Map<string, 'alive' | 'dead'> {
  try {
    const raw = sessionStorage.getItem(CACHE_KEY)
    if (raw) return new Map(Object.entries(JSON.parse(raw)))
  } catch {
    // private mode, quota, corrupt entry — the cache is an optimisation only
  }
  return new Map()
}

function remember(hash: string, status: 'alive' | 'dead') {
  cache.set(hash, status)
  try {
    sessionStorage.setItem(CACHE_KEY, JSON.stringify(Object.fromEntries(cache)))
  } catch {
    // ignore: losing the cache costs a re-probe, nothing more
  }
}

/** true = served, false = gone (404), null = no verdict (timeout, 5xx, network). */
async function probe(url: string, signal: AbortSignal): Promise<boolean | null> {
  const res = await fetch(url, { method: 'GET', headers: { Range: 'bytes=0-0' }, signal })
  // 206 for a served range, 200 for a gateway that ignores Range.
  if (res.status === 200 || res.status === 206) return true
  // 404 is what both read paths answer for an unpaid chunk — the one answer
  // that means "expired". A 5xx is a gateway having a bad moment, not a verdict.
  if (res.status === 404) return false
  return null
}

export function useBzzStatus(readUrl: string, hash: string | undefined): BzzStatus {
  const [status, setStatus] = useState<BzzStatus>(() =>
    hash ? cache.get(hash) ?? 'checking' : 'checking',
  )

  useEffect(() => {
    if (!hash) return
    const known = cache.get(hash)
    if (known) {
      setStatus(known)
      return
    }

    setStatus('checking')
    const controller = new AbortController()
    let timedOut = false
    const timer = setTimeout(() => { timedOut = true; controller.abort() }, PROBE_TIMEOUT_MS)

    probe(`${readUrl}/bzz/${hash}`, controller.signal)
      .then(ok => {
        if (ok === null) {
          // Not cached: the next render asks again, and meanwhile the image
          // loader gets its chance, with retries, instead of a hidden tile.
          setStatus('alive')
          return
        }
        remember(hash, ok ? 'alive' : 'dead')
        setStatus(ok ? 'alive' : 'dead')
      })
      .catch(() => {
        // A timeout past 20s, or a network failure. That used to be cached as
        // dead, which hid tiles (and told the detail page the image had
        // expired) whenever the gateway was merely slow. It is no verdict:
        // let SwarmImage try, with retries, and do not remember it.
        if (!controller.signal.aborted || timedOut) setStatus('alive')
      })
      .finally(() => clearTimeout(timer))

    return () => {
      clearTimeout(timer)
      controller.abort()
    }
  }, [readUrl, hash])

  return status
}

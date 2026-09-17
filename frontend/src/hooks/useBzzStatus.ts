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
 * live reference re-checks on the next page load, which is often enough.
 */
export type BzzStatus = 'checking' | 'alive' | 'dead'

// Measured against both read paths before picking this: a Bee node gives up on
// an unpayable chunk after ~7s, api.gateway.ethswarm.org after ~14s. A timeout
// shorter than that aborts before the 404 arrives, so the answer never gets
// cached and every render pays the wait again.
const PROBE_TIMEOUT_MS = 20_000
const CACHE_KEY = 'bzz-status-v1'

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

async function probe(url: string, signal: AbortSignal): Promise<boolean> {
  const res = await fetch(url, { method: 'GET', headers: { Range: 'bytes=0-0' }, signal })
  // 206 for a served range, 200 for a gateway that ignores Range. Anything else
  // — 404 for an unpaid chunk, 5xx from a gateway that gave up — is dead.
  return res.status === 200 || res.status === 206
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
    const timer = setTimeout(() => controller.abort(), PROBE_TIMEOUT_MS)

    probe(`${readUrl}/bzz/${hash}`, controller.signal)
      .then(ok => {
        remember(hash, ok ? 'alive' : 'dead')
        setStatus(ok ? 'alive' : 'dead')
      })
      .catch(() => {
        // A timeout past 20s, or a network failure. Cached as dead for the
        // session either way: to someone looking at the page, content that
        // never arrives and content that 404s are the same thing, and the cache
        // is dropped on the next page load so a slow day is not permanent.
        remember(hash, 'dead')
        setStatus('dead')
      })
      .finally(() => clearTimeout(timer))

    return () => {
      clearTimeout(timer)
      controller.abort()
    }
  }, [readUrl, hash])

  return status
}

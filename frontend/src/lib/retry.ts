/**
 * Backoff shared by everything that reads from Swarm. A gateway that could not
 * fetch a chunk in time often has it on the next try (the first attempt pulled
 * it into its cache), so a few spaced retries turn most "failed to load" into
 * a short wait.
 */
export const RETRIES = 4 // after the first attempt: waits 1s, 2s, 4s, 8s

export const retryDelayMs = (attempt: number) => 1000 * 2 ** attempt

/** Run fn, retrying with backoff until it succeeds, retries run out, or isCancelled. */
export async function withRetry<T>(
  fn: (attempt: number) => Promise<T>,
  isCancelled: () => boolean,
  onRetry?: (attempt: number) => void,
): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await fn(attempt)
    } catch (e) {
      if (attempt >= RETRIES || isCancelled()) throw e
      onRetry?.(attempt + 1)
      await new Promise(r => setTimeout(r, retryDelayMs(attempt)))
      if (isCancelled()) throw e
    }
  }
}

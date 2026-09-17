/**
 * viem/wagmi errors carry a long multi line message. Show the short form when there is one,
 * so a rejected wallet prompt or a reverted transaction reads as a single line.
 */
export function txErrorMessage(error: unknown): string {
  const e = error as { shortMessage?: string; message?: string } | null
  return e?.shortMessage || e?.message?.split('\n')[0] || 'Transaction failed'
}

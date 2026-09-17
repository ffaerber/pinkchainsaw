import { useEffect } from 'react'
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import toast from 'react-hot-toast'
import { PINKCHAINSAW_ABI, PINKCHAINSAW_ADDRESS } from '../config/contracts'
import { useBeeContext } from '../hooks/BeeContext'
import { usePostingBatch } from '../hooks/usePostingBatch'
import { txErrorMessage } from '../lib/errors'

/**
 * The part of "connected" that belongs to this contract rather than to Swarm.
 *
 * The contract binds an author to one postage batch: the first post registers
 * it, later posts must reuse it, and changing it is an on-chain setBatchId call.
 * swarm-connect picks which stamp the node uploads with — it has no reason to
 * know that a contract elsewhere has an opinion about which stamp that must be.
 *
 * Renders nothing while the two agree, which is the normal case. It appears
 * when the registered batch is missing from this node (the author moved nodes
 * or let a batch lapse) or when the stamp selected in the connect modal is not
 * the one posts pay into — the two states where a post would revert with
 * "batch not registered to sender", or silently pay into the wrong batch.
 */
export default function PostingBatch() {
  const { batchId, isConnected } = useBeeContext()
  const { registeredBatchId, registeredBatchOnNode, refetchRegisteredBatch } = usePostingBatch()

  const { writeContract, data: txHash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  useEffect(() => {
    if (isSuccess) { toast.success('Stamp registered!'); refetchRegisteredBatch() }
  }, [isSuccess, refetchRegisteredBatch])

  useEffect(() => {
    if (error) toast.error(txErrorMessage(error))
  }, [error])

  if (!isConnected) return null

  const mismatch = !!registeredBatchId && !!batchId && batchId !== registeredBatchId
  const missingOnNode = !!registeredBatchId && !registeredBatchOnNode
  if (!mismatch && !missingOnNode) return null

  const busy = isPending || isConfirming

  return (
    <div className="mr-2 text-xs text-[#888] flex items-center gap-2">
      <span>
        {missingOnNode
          ? 'Posts pay into a stamp this node does not have'
          : 'Posts pay into a different stamp than the one selected'}
      </span>
      {batchId && (
        <button
          onClick={() =>
            writeContract({
              address: PINKCHAINSAW_ADDRESS,
              abi: PINKCHAINSAW_ABI,
              functionName: 'setBatchId',
              args: [`0x${batchId.replace(/^0x/, '')}` as `0x${string}`],
            })
          }
          disabled={busy}
          className="px-2 py-1 border border-[#e84393] text-[#e84393] rounded cursor-pointer hover:bg-[#e84393] hover:text-white disabled:opacity-50"
        >
          {busy ? 'registering…' : 'use the selected stamp'}
        </button>
      )}
    </div>
  )
}

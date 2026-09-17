import { useAccount, useReadContract } from 'wagmi'
import { zeroHash } from 'viem'
import { PINKCHAINSAW_ABI, PINKCHAINSAW_ADDRESS } from '../config/contracts'
import { useBeeContext } from './BeeContext'

/**
 * The contract binds an author to a single postage batch: the first post registers it and every
 * later post has to reuse it, until the author rotates it with setBatchId. Posting therefore has
 * to use the registered batch rather than whichever batch the local Bee node happens to list
 * first, otherwise the transaction reverts with "batch not registered to sender".
 *
 * The upload uses the same batch as the top up, so an author's content and the batch their fees
 * keep alive never drift apart.
 */
export function usePostingBatch() {
  const { address } = useAccount()
  const { batchId: selectedBatchId, allBatches, isConnected: beeConnected } = useBeeContext()

  const { data, refetch: refetchRegisteredBatch } = useReadContract({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    functionName: 'getBatchId',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  })

  const raw = data as string | undefined
  // bee-js reports batch ids without a 0x prefix, the contract returns a bytes32 with one
  const registeredBatchId = raw && raw !== zeroHash ? raw.replace(/^0x/, '') : null

  // A registered batch that the local node does not hold cannot be uploaded with, which happens
  // when an author moves to a new node or lets a batch expire. They need to rotate.
  const registeredBatchOnNode =
    !registeredBatchId || !beeConnected || allBatches.some(b => b.batchID.toString() === registeredBatchId)

  return {
    registeredBatchId,
    registeredBatchOnNode,
    selectedBatchId,
    /** The batch a new post must upload with and pay into. */
    postingBatchId: registeredBatchId ?? selectedBatchId,
    refetchRegisteredBatch,
  }
}

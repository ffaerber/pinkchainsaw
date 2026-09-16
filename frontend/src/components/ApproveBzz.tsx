import { useEffect } from 'react'
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { maxUint256 } from 'viem'
import { BZZ_TOKEN_ADDRESS, ERC20_ABI, PINKCHAINSAW_ADDRESS } from '../config/contracts'

/**
 * The one connect step swarm-connect cannot cover: this contract pulls xBZZ
 * from the poster on every thread, comment and vote, so it needs an ERC-20
 * allowance. That is a fact about pinkchainsaw, not about Swarm — swarm-connect
 * checks that the wallet *holds* xBZZ, and stops there, correctly.
 *
 * Renders nothing once an allowance exists, so it is invisible in the normal
 * case and only appears when posting would otherwise fail silently: UploadTile
 * and the comment box just disable themselves without one.
 */
export default function ApproveBzz() {
  const { address, isConnected } = useAccount()

  const { data: allowance, refetch } = useReadContract({
    address: BZZ_TOKEN_ADDRESS,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, PINKCHAINSAW_ADDRESS] : undefined,
    query: { enabled: !!address },
  })

  const { writeContract, data: txHash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  useEffect(() => {
    if (isSuccess) refetch()
  }, [isSuccess, refetch])

  if (!isConnected || (allowance as bigint | undefined) === undefined) return null
  if ((allowance as bigint) > 0n) return null

  return (
    <button
      onClick={() =>
        writeContract({
          address: BZZ_TOKEN_ADDRESS,
          abi: ERC20_ABI,
          functionName: 'approve',
          args: [PINKCHAINSAW_ADDRESS, maxUint256],
        })
      }
      disabled={isPending || isConfirming}
      className="text-sm px-3 py-1.5 mr-2 border border-[#e84393] text-[#e84393] rounded cursor-pointer hover:bg-[#e84393] hover:text-white disabled:opacity-50"
      title="pinkchainsaw spends xBZZ on your behalf for posts, comments and votes"
    >
      {isPending || isConfirming ? 'Approving…' : 'Approve xBZZ'}
    </button>
  )
}

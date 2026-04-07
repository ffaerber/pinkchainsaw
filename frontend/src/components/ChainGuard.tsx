import { useAccount, useSwitchChain } from 'wagmi'
import { gnosis } from 'wagmi/chains'

export default function ChainGuard() {
  const { isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()

  if (!isConnected || chainId === gnosis.id) return null

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/90">
      <div className="bg-[#1b1e1f] border border-[#252525] rounded-lg p-8 max-w-md text-center">
        <h2 className="text-lg font-semibold text-[#f2f5f4] mb-3">Wrong Network</h2>
        <p className="text-sm text-[#888] mb-6">
          Pink Chainsaw runs on Gnosis Chain.
        </p>
        <button
          onClick={() => switchChain({ chainId: gnosis.id })}
          className="px-6 py-2 bg-[#e84393] text-white text-sm rounded hover:brightness-110 cursor-pointer"
        >
          Switch to Gnosis Chain
        </button>
      </div>
    </div>
  )
}

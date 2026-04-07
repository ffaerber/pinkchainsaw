import { useAccount, useBalance, useConnect, useDisconnect, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { maxUint256 } from 'viem'
import { BZZ_TOKEN_ADDRESS, ERC20_ABI, PINKCHAINSAW_ADDRESS } from '../config/contracts'
import { useBeeContext } from '../hooks/BeeContext'

interface ModalProps {
  handleClose: () => void
}

export default function Modal({ handleClose }: ModalProps) {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()
  const { isConnected: beeConnected, peerCount, allBatches, batchId, selectBatch, beeUrl, updateBeeUrl } = useBeeContext()

  const { data: xdaiBalance } = useBalance({ address })
  const hasXdai = xdaiBalance && xdaiBalance.value > 0n

  const { data: bzzBalance } = useReadContract({
    address: BZZ_TOKEN_ADDRESS, abi: ERC20_ABI, functionName: 'balanceOf',
    args: address ? [address] : undefined, query: { enabled: !!address },
  })
  const hasBzz = bzzBalance && (bzzBalance as bigint) > 0n

  const { data: bzzAllowance } = useReadContract({
    address: BZZ_TOKEN_ADDRESS, abi: ERC20_ABI, functionName: 'allowance',
    args: address ? [address, PINKCHAINSAW_ADDRESS] : undefined, query: { enabled: !!address },
  })
  const hasAllowance = bzzAllowance && (bzzAllowance as bigint) > 0n

  const { writeContract, data: approveTxHash } = useWriteContract()
  const { isSuccess: approveSuccess } = useWaitForTransactionReceipt({ hash: approveTxHash })

  const handleApprove = () => {
    writeContract({ address: BZZ_TOKEN_ADDRESS, abi: ERC20_ABI, functionName: 'approve', args: [PINKCHAINSAW_ADDRESS, maxUint256] })
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/90">
      <div className="bg-[#1b1e1f] border border-[#252525] rounded-lg max-w-md w-full mx-4">
        <div className="p-5">
          <h3 className="text-base font-semibold text-[#f2f5f4] mb-4">Connect</h3>
          <ul className="text-sm space-y-2">
            <li className="flex items-start gap-2">
              <span className={isConnected ? 'text-green-500' : 'text-red-500'}>{isConnected ? '+' : 'x'}</span>
              <div className="flex-1">
                {isConnected ? (
                  <span className="text-[#f2f5f4]">
                    <span className="font-mono">{address?.slice(0, 6)}...{address?.slice(-4)}</span>
                    {' — '}
                    <a onClick={() => disconnect()} className="text-[#e84393] underline cursor-pointer">disconnect</a>
                  </span>
                ) : (
                  <span className="text-[#888]">No wallet — <a onClick={() => connect({ connector: connectors[0] })} className="text-[#e84393] underline cursor-pointer">connect now</a></span>
                )}
              </div>
            </li>
            <Check ok={!!hasXdai} label="xDAI funded" fail={<>No xDAI — get some at <a target="_blank" href="https://ramp.network/buy/" className="text-[#e84393] underline">ramp.network</a></>} />
            <Check ok={!!hasBzz} label="xBZZ funded" fail={<>No xBZZ — swap at <a target="_blank" href="https://honeyswap.org/" className="text-[#e84393] underline">honeyswap.org</a></>} />
            <Check ok={!!hasAllowance || approveSuccess} label="xBZZ approved" fail={<>No allowance — <a onClick={handleApprove} className="text-[#e84393] underline cursor-pointer">approve now</a></>} />
            <li className="flex items-start gap-2">
              <span className={beeConnected ? 'text-green-500' : 'text-red-500'}>{beeConnected ? '+' : 'x'}</span>
              <div className="flex-1">
                <span className={beeConnected ? 'text-[#f2f5f4]' : 'text-[#888]'}>
                  {beeConnected ? 'Bee node running' : <>Install <a target="_blank" href="https://www.ethswarm.org/build/desktop" className="text-[#e84393] underline">Swarm Desktop</a> or set URL</>}
                </span>
                <input
                  type="text"
                  value={beeUrl}
                  onChange={e => updateBeeUrl(e.target.value)}
                  placeholder="http://localhost:1633"
                  className="mt-1 w-full bg-[#161618] border border-[#252525] rounded text-sm text-[#f2f5f4] p-1"
                />
              </div>
            </li>
            <Check ok={peerCount > 0} label={`Swarm peers: ${peerCount}`} fail="No peers connected" />

            <li className="flex items-start gap-2">
              {allBatches.length > 0 ? (
                <>
                  <span className={batchId ? 'text-green-500' : 'text-yellow-500'}>{batchId ? '+' : '!'}</span>
                  <div className="flex-1">
                    <select
                      value={batchId || ''}
                      onChange={e => selectBatch(e.target.value)}
                      className="w-full bg-[#161618] border border-[#252525] rounded text-sm text-[#f2f5f4] p-1"
                    >
                      <option value="">select stamp</option>
                      {allBatches.filter(b => b.usable).map(b => (
                        <option key={b.batchID.toString()} value={b.batchID.toString()}>
                          {b.label || b.batchID.toString().slice(0, 16) + '...'}
                        </option>
                      ))}
                    </select>
                  </div>
                </>
              ) : (
                <>
                  <span className="text-red-500">x</span>
                  <span className="text-[#888]">No postage stamps — create one in Swarm Desktop</span>
                </>
              )}
            </li>
          </ul>
        </div>
        <div className="border-t border-[#252525] px-5 py-3 flex justify-end">
          <button onClick={handleClose} className="px-4 py-1.5 bg-[#e84393] text-white text-sm rounded hover:brightness-110 cursor-pointer">
            OK
          </button>
        </div>
      </div>
    </div>
  )
}

function Check({ ok, label, fail }: { ok: boolean, label: string, fail: React.ReactNode }) {
  return (
    <li className="flex items-start gap-2">
      <span className={ok ? 'text-green-500' : 'text-red-500'}>{ok ? '+' : 'x'}</span>
      <span className={ok ? 'text-[#f2f5f4]' : 'text-[#888]'}>{ok ? label : fail}</span>
    </li>
  )
}

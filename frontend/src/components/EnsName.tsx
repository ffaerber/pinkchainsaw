import { useEffect, useState } from 'react'
import { createPublicClient, http } from 'viem'
import { mainnet } from 'viem/chains'

const ensClient = createPublicClient({
  chain: mainnet,
  transport: http('https://eth.llamarpc.com'),
})

const cache = new Map<string, string | null>()

export default function EnsName({ address, className }: { address: string; className?: string }) {
  const [name, setName] = useState<string | null>(null)
  const short = `${address.slice(0, 6)}...${address.slice(-4)}`

  useEffect(() => {
    if (cache.has(address)) {
      setName(cache.get(address)!)
      return
    }
    ensClient.getEnsName({ address: address as `0x${string}` })
      .then(n => { cache.set(address, n); setName(n) })
      .catch(() => { cache.set(address, null) })
  }, [address])

  return (
    <span className={className} title={address}>
      {name || short}
    </span>
  )
}

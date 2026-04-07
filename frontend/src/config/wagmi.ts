import { http, createConfig } from 'wagmi'
import { gnosis } from 'wagmi/chains'
import { injected } from 'wagmi/connectors'

// For local dev with Anvil fork, override the RPC
const rpcUrl = import.meta.env.VITE_RPC_URL || 'https://rpc.gnosischain.com'

const gnosisChain = {
  ...gnosis,
  rpcUrls: {
    default: {
      http: [rpcUrl],
    },
  },
} as const

export const config = createConfig({
  chains: [gnosisChain],
  connectors: [injected()],
  transports: {
    [gnosis.id]: http(rpcUrl),
  },
})

declare module 'wagmi' {
  interface Register {
    config: typeof config
  }
}

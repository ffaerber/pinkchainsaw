import pinkchainsawAbi from '../abi/Pinkchainsaw.json'

export const BZZ_TOKEN_ADDRESS = '0xdBF3Ea6F5beE45c02255B2c26a16F300502F68da' as const

/// xBZZ uses 16 decimals rather than the usual 18
export const BZZ_DECIMALS = 16

// Deployed proxy on Gnosis Chain. Override for local Anvil runs via frontend/.env
export const PINKCHAINSAW_ADDRESS = (import.meta.env.VITE_CONTRACT_ADDRESS
  || '0x95cBdd7d64040C101240c93fc7B55EC6c2679368') as `0x${string}`

export const PINKCHAINSAW_ABI = pinkchainsawAbi as readonly any[]

export const ERC20_ABI = [
  {
    type: 'function',
    name: 'balanceOf',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'allowance',
    inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'approve',
    inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }],
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'symbol',
    inputs: [],
    outputs: [{ name: '', type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'decimals',
    inputs: [],
    outputs: [{ name: '', type: 'uint8' }],
    stateMutability: 'view',
  },
] as const

// The batch a first post registers on chain when the author has none yet.
// Without it the app takes the first usable batch the node reports, which on a
// node running other services can be any of them — and the author is then bound
// to a batch that has nothing to do with this app (the contract binds one batch
// per author; see usePostingBatch). Users can still pick another in the connect
// modal before their first post.
export const PREFERRED_BATCH_ID = '35b2db745f578fff78009be8f87c253f73272d179c66d0020710bbc1d1a9e517'

export const BEE_GATEWAY_URL = import.meta.env.VITE_BEE_GATEWAY_URL || 'https://api.gateway.ethswarm.org'
export const BEE_API_URL = import.meta.env.VITE_BEE_API_URL || 'http://localhost:1633'
// llamarpc stopped answering browsers: its CORS preflight returns 525 (a TLS
// failure at its edge), so every ENS lookup fails with "Failed to fetch" and
// viem retries it three times per mount -- which is most of what fills the
// console on a thread page. publicnode answers the preflight and resolves.
// Point VITE_ENS_RPC_URL at your own mainnet node if you run one.
export const ENS_RPC_URL = import.meta.env.VITE_ENS_RPC_URL || 'https://ethereum-rpc.publicnode.com'

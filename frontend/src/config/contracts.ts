import pinkchainsawAbi from '../abi/Pinkchainsaw.json'

export const BZZ_TOKEN_ADDRESS = '0xdBF3Ea6F5beE45c02255B2c26a16F300502F68da' as const

export const PINKCHAINSAW_ADDRESS = '0x95cBdd7d64040C101240c93fc7B55EC6c2679368' as `0x${string}`

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

// The batch uploads should be stamped with. Without this the app takes the first
// usable batch the node reports, which on a node that also runs other services
// can be any of them — and content then lives or dies by a batch that has
// nothing to do with this app. Users can still pick another batch by hand.
export const PREFERRED_BATCH_ID = '35b2db745f578fff78009be8f87c253f73272d179c66d0020710bbc1d1a9e517'

export const BEE_GATEWAY_URL = 'https://api.gateway.ethswarm.org'
export const BEE_API_URL = 'http://localhost:1633'

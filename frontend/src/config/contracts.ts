import pinkchainsawAbi from '../abi/Pinkchainsaw.json'

export const BZZ_TOKEN_ADDRESS = '0xdBF3Ea6F5beE45c02255B2c26a16F300502F68da' as const

export const PINKCHAINSAW_ADDRESS = '0xFe73D7bBA8A6228Aa3Aa4f955A1031eb0E83f90e' as `0x${string}`

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

export const BEE_GATEWAY_URL = 'https://api.gateway.ethswarm.org'
export const BEE_API_URL = 'http://localhost:1633'

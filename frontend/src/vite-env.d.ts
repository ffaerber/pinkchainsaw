/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_CONTRACT_ADDRESS: string
  readonly VITE_RPC_URL: string
  readonly VITE_BEE_GATEWAY_URL: string
  readonly VITE_BEE_API_URL: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}

import { createContext, useContext } from 'react'
import type { ReactNode } from 'react'
import { useBee } from './useBee'

type BeeContextType = ReturnType<typeof useBee>

const BeeContext = createContext<BeeContextType | null>(null)

export function BeeProvider({ children }: { children: ReactNode }) {
  const bee = useBee()
  return <BeeContext.Provider value={bee}>{children}</BeeContext.Provider>
}

export function useBeeContext() {
  const ctx = useContext(BeeContext)
  if (!ctx) throw new Error('useBeeContext must be used within BeeProvider')
  return ctx
}

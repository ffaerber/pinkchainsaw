import { WagmiProvider } from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { HashRouter, Routes, Route } from 'react-router'
import { Toaster } from 'react-hot-toast'
import { useAccount } from 'wagmi'
import { config } from './config/wagmi'
import { BeeProvider } from './hooks/BeeContext'
import ChainGuard from './components/ChainGuard'
import Nav from './components/Nav'
import ThreadList from './components/ThreadList'
import ThreadDetails from './components/ThreadDetails'
import Modal from './components/Modal'
import { useState } from 'react'

const queryClient = new QueryClient()

function AppContent() {
  const { isConnected } = useAccount()
  const [modalOpen, setModalOpen] = useState(false)

  return (
    <BeeProvider>
      <HashRouter>
        {isConnected && <ChainGuard />}
        <Nav onConnectClick={() => setModalOpen(true)} />
        {modalOpen && (
          <Modal handleClose={() => setModalOpen(false)} />
        )}
        <Routes>
          <Route path="/" element={<ThreadList />} />
          <Route path="/threads/:threadId" element={<ThreadDetails />} />
        </Routes>
        <Toaster
          position="bottom-right"
          toastOptions={{
            style: { background: '#1b1e1f', color: '#f2f5f4', border: '1px solid #252525' },
          }}
        />
      </HashRouter>
    </BeeProvider>
  )
}

export default function App() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <AppContent />
      </QueryClientProvider>
    </WagmiProvider>
  )
}

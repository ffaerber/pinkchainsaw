import { SwarmConnectModal } from '@ffaerber/swarm-connect'
import { useBeeContext } from '../hooks/BeeContext'

/**
 * The connect modal, fed from the app's single useSwarmConnect instance so the
 * node URL and the stamp picked here are the same ones the upload paths use.
 * Passing the state in is what the package's modal is shaped for; letting it
 * create its own would give the app two disagreeing copies.
 */
export default function ConnectModal({ onClose }: { onClose: () => void }) {
  const { swarm } = useBeeContext()

  return (
    <SwarmConnectModal
      onClose={onClose}
      beeNode={swarm.beeNode}
      stamps={swarm.stamps}
      beeApiUrl={swarm.beeApiUrl}
      setBeeApiUrl={swarm.setBeeApiUrl}
      beeApiKey={swarm.beeApiKey}
      setBeeApiKey={swarm.setBeeApiKey}
      requirements={swarm.requirements}
      nodeWallet={swarm.nodeWallet}
    />
  )
}

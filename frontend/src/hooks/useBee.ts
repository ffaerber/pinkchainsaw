import { useEffect, useMemo } from 'react'
import { Bee } from '@ethersphere/bee-js'
import { useSwarmConnect } from '@ffaerber/swarm-connect'
import { BEE_GATEWAY_URL, PINKCHAINSAW_ADDRESS, PREFERRED_BATCH_ID } from '../config/contracts'

/**
 * Adapter between @ffaerber/swarm-connect and the rest of the app.
 *
 * swarm-connect owns everything about reaching Swarm: which Bee node, whether
 * it is up, which postage stamp, and the wallet checks in front of them. This
 * hook turns that into what the components here actually hold — a reader, a
 * writer, a URL for <img src>, and a batch id — and nothing else. It is the
 * single instance of useSwarmConnect in the app, so the connect modal and the
 * upload paths are looking at the same state rather than two copies of it.
 */
export function useBee() {
  const swarm = useSwarmConnect({
    // Posting costs xDAI for gas and xBZZ for fees, and uploading needs a
    // stamp. The contract pulls the fees itself, so it also needs an allowance
    // — without one the upload tile and the comment box quietly disable
    // themselves. The node's own wallet is not used: this app never buys stamps.
    requirements: {
      xdai: true,
      xbzz: true,
      xbzzAllowance: { spender: PINKCHAINSAW_ADDRESS },
      nodeWallet: false,
      postageStamp: true,
    },
  })

  const { beeApiUrl, beeNode, stamps } = swarm
  const isConnected = beeNode.isRunning

  const localBee = useMemo(() => new Bee(beeApiUrl), [beeApiUrl])
  const gatewayBee = useMemo(() => new Bee(BEE_GATEWAY_URL), [])

  // Default to this app's own batch when the node has it and the user has not
  // chosen otherwise. Without this the first stamp in the list wins, which on a
  // node running more than one service is how an upload ends up paid for by a
  // batch belonging to something else — and dies when that batch lapses.
  useEffect(() => {
    if (stamps.selectedStampId || stamps.stamps.length === 0) return
    const preferred = stamps.stamps.find(
      s => s.batchID.replace(/^0x/, '') === PREFERRED_BATCH_ID && s.usable,
    )
    if (preferred) stamps.selectStamp(preferred.batchID)
  }, [stamps])

  return {
    // The shared connect state, for the modal in App.tsx.
    swarm,
    // Read through the local node when it is up, the public gateway otherwise.
    reader: isConnected ? localBee : gatewayBee,
    // Writes always need the local node: uploads are stamped there.
    writer: localBee,
    // Base URL for <img src> tags.
    readUrl: isConnected ? beeApiUrl : BEE_GATEWAY_URL,
    batchId: stamps.selectedStampId ?? null,
    isConnected,
  }
}

import { useEffect, useMemo } from 'react'
import { Bee } from '@ethersphere/bee-js'
import { useSwarmConnect } from '@ffaerber/swarm-connect'
import { BEE_GATEWAY_URL, PINKCHAINSAW_ADDRESS, PREFERRED_BATCH_ID } from '../config/contracts'

/**
 * Adapter between @ffaerber/swarm-connect and the rest of the app.
 *
 * swarm-connect owns everything about reaching Swarm: which Bee node, whether it
 * is up, which postage stamp, and the wallet checks in front of them. This hook
 * turns that into what the components here hold — a reader, a writer, a URL for
 * <img src>, and a batch — and nothing else. It is the single instance of
 * useSwarmConnect in the app, so the connect modal and the upload paths look at
 * the same state rather than two copies of it.
 *
 * `allBatches` stays on the surface because usePostingBatch needs it: the
 * contract binds an author to one batch, and it has to know whether the
 * registered batch is actually on this node before letting a post through.
 */
export function useBee() {
  const swarm = useSwarmConnect({
    // Posting costs xDAI for gas and xBZZ for fees, uploading needs a stamp, and
    // the contract pulls the fees itself, so it also needs an allowance.
    // The node's own wallet is not used: this app never buys stamps.
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

  // Default to this app's batch when the node has it and the user has not chosen
  // otherwise. It decides which batch a first post registers on chain — and that
  // binding is durable, so "whichever batch the node listed first" is a poor
  // default on a node that runs more than one service.
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
    allBatches: stamps.stamps,
    selectBatch: stamps.selectStamp,
    isConnected,
  }
}

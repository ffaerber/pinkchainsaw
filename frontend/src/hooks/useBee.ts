import { useState, useEffect, useMemo, useCallback } from 'react'
import { Bee } from '@ethersphere/bee-js'
import type { PostageBatch, Topology } from '@ethersphere/bee-js'
import { BEE_API_URL, BEE_GATEWAY_URL } from '../config/contracts'

export function useBee() {
  const [beeUrl, setBeeUrl] = useState(() => localStorage.getItem('bee-api-url') || BEE_API_URL)
  const localBee = useMemo(() => new Bee(beeUrl), [beeUrl])
  const gatewayBee = useMemo(() => new Bee(BEE_GATEWAY_URL), [])

  const updateBeeUrl = useCallback((url: string) => {
    localStorage.setItem('bee-api-url', url)
    setBeeUrl(url)
  }, [])

  const [batchId, setBatchId] = useState<string | null>(null)
  const [allBatches, setAllBatches] = useState<PostageBatch[]>([])
  const [topology, setTopology] = useState<Topology | null>(null)
  const [isConnected, setIsConnected] = useState(false)

  // Check local Bee node health (with timeout to avoid hanging on mixed-content blocks)
  useEffect(() => {
    const timeout = new Promise<never>((_, reject) => setTimeout(() => reject('timeout'), 3000))
    Promise.race([localBee.isConnected(), timeout])
      .then(setIsConnected)
      .catch(() => setIsConnected(false))
  }, [localBee])

  // Fetch topology from local node
  useEffect(() => {
    if (!isConnected) return
    localBee.getTopology()
      .then(setTopology)
      .catch(() => {})
  }, [localBee, isConnected])

  // Fetch postage batches from local node
  useEffect(() => {
    if (!isConnected) return
    localBee.getAllPostageBatch()
      .then(batches => {
        setAllBatches(batches)
        const usable = batches.find(b => b.usable)
        if (usable) {
          setBatchId(usable.batchID.toString())
        }
      })
      .catch(() => {})
  }, [localBee, isConnected])

  const selectBatch = (id: string) => {
    setBatchId(id)
  }

  return {
    // Read: use local node if connected, otherwise fall back to public gateway
    reader: isConnected ? localBee : gatewayBee,
    // Write: always local node (requires BZZ postage stamps)
    writer: localBee,
    // Read base URL for <img src> tags
    readUrl: isConnected ? beeUrl : BEE_GATEWAY_URL,
    beeUrl,
    updateBeeUrl,
    batchId,
    allBatches,
    topology,
    isConnected,
    peerCount: topology?.connected ?? 0,
    selectBatch,
  }
}

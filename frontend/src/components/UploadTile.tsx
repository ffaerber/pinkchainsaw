import { useCallback, useEffect } from 'react'
import { useDropzone } from 'react-dropzone'
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import toast from 'react-hot-toast'
import { PINKCHAINSAW_ABI, PINKCHAINSAW_ADDRESS, BZZ_TOKEN_ADDRESS, ERC20_ABI } from '../config/contracts'
import { useBeeContext } from '../hooks/BeeContext'

export default function UploadTile() {
  const { isConnected, address } = useAccount()
  const { writer, batchId } = useBeeContext()

  const { data: bzzAllowance } = useReadContract({
    address: BZZ_TOKEN_ADDRESS, abi: ERC20_ABI, functionName: 'allowance',
    args: address ? [address, PINKCHAINSAW_ADDRESS] : undefined, query: { enabled: !!address },
  })
  const hasAllowance = bzzAllowance && (bzzAllowance as bigint) > 0n

  const { writeContract, data: txHash } = useWriteContract()
  const { isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  useEffect(() => {
    if (isSuccess) toast.success('Thread created!')
  }, [isSuccess])

  const onDrop = useCallback(async (acceptedFiles: File[]) => {
    const file = acceptedFiles[0]
    if (!file || !batchId) return
    try {
      toast('Uploading to Swarm...')
      const tag = await writer.createTag()
      const { reference } = await writer.uploadFile(batchId, file, file.name, {
        tag: tag.uid,
        contentType: file.type,
      })
      writeContract({
        address: PINKCHAINSAW_ADDRESS,
        abi: PINKCHAINSAW_ABI,
        functionName: 'createThread',
        args: [`0x${reference}`, `0x${batchId}`],
      })
    } catch (e) {
      toast.error(`Upload failed: ${e}`)
    }
  }, [writer, batchId, writeContract])

  const enabled = isConnected && !!batchId && !!hasAllowance

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    multiple: false,
    disabled: !enabled,
    accept: { 'image/jpeg': [], 'image/png': [], 'image/gif': [], 'image/webp': [] },
  })

  return (
    <div
      {...getRootProps()}
      className={`w-[128px] h-[128px] border-2 border-dashed rounded flex items-center justify-center transition-colors ${
        enabled
          ? isDragActive
            ? 'border-[#e84393] bg-[#e84393]/10 cursor-pointer'
            : 'border-[#444] hover:border-[#e84393] cursor-pointer'
          : 'border-[#333] cursor-not-allowed opacity-40'
      }`}
    >
      <input {...getInputProps()} />
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className={`w-8 h-8 ${enabled ? 'text-[#888]' : 'text-[#444]'}`}>
        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
        <polyline points="17 8 12 3 7 8" />
        <line x1="12" y1="3" x2="12" y2="15" />
      </svg>
    </div>
  )
}

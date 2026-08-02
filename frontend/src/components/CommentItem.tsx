import { useEffect, useState } from 'react'
import { useAccount, useReadContract, useWatchContractEvent, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import toast from 'react-hot-toast'
import { PINKCHAINSAW_ABI, PINKCHAINSAW_ADDRESS, BZZ_TOKEN_ADDRESS, ERC20_ABI } from '../config/contracts'
import { useBeeContext } from '../hooks/BeeContext'
import { usePostingBatch } from '../hooks/usePostingBatch'
import { txErrorMessage } from '../lib/errors'
import EnsName from './EnsName'

// Reply chains are unbounded on chain, so stop recursing before a deep chain can
// exhaust the render stack. Deeper replies stay reachable from the last rendered comment.
const MAX_DEPTH = 12

interface CommentItemProps {
  commentId: string
  depth: number
}

export default function CommentItem({ commentId, depth }: CommentItemProps) {
  const { address } = useAccount()
  const { reader, writer } = useBeeContext()
  const { postingBatchId: batchId, refetchRegisteredBatch } = usePostingBatch()

  const { data: bzzAllowance } = useReadContract({
    address: BZZ_TOKEN_ADDRESS, abi: ERC20_ABI, functionName: 'allowance',
    args: address ? [address, PINKCHAINSAW_ADDRESS] : undefined, query: { enabled: !!address },
  })
  const canWrite = !!address && !!batchId && bzzAllowance && (bzzAllowance as bigint) > 0n

  const { data: comment, refetch } = useReadContract({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    functionName: 'getComment',
    args: [commentId as `0x${string}`],
  })

  const post = comment as any

  // Download comment text from Swarm
  const [commentText, setCommentText] = useState('')
  useEffect(() => {
    if (!post?.bzzhash) return
    const hash = (post.bzzhash as string).replace('0x', '')
    reader.downloadData(hash)
      .then(data => setCommentText(data.toUtf8()))
      .catch(() => setCommentText('[failed to load]'))
  }, [reader, post?.bzzhash])

  // The vote this account has already cast: 1, -1, or 0
  const { data: myVote, refetch: refetchVote } = useReadContract({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    functionName: 'getVote',
    args: address ? [commentId as `0x${string}`, address] : undefined,
    query: { enabled: !!address },
  })
  const castVote = Number(myVote ?? 0)

  // Refresh when anyone votes on or replies to this comment
  useWatchContractEvent({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    eventName: 'CommentUpdated',
    onLogs(logs) {
      if (logs.some(log => (log as any).args?.id === commentId)) refetch()
    },
  })

  // Voting
  const { writeContract: writeVote, data: voteTxHash, isPending: votePending } = useWriteContract({
    mutation: { onError: (err) => toast.error(txErrorMessage(err)) },
  })
  const { isSuccess: voteSuccess } = useWaitForTransactionReceipt({ hash: voteTxHash })

  useEffect(() => {
    if (voteSuccess) { toast.success('Vote recorded!'); refetch(); refetchVote() }
  }, [voteSuccess, refetch, refetchVote])

  const handleVote = (fn: 'upVote' | 'downVote') => {
    writeVote({
      address: PINKCHAINSAW_ADDRESS,
      abi: PINKCHAINSAW_ABI,
      functionName: fn,
      args: [commentId as `0x${string}`],
    })
  }

  // Reply
  const [replyOpen, setReplyOpen] = useState(false)
  const [newComment, setNewComment] = useState('')
  const [uploading, setUploading] = useState(false)
  const { writeContract: writeReply, data: replyTxHash, isPending: replyPending } = useWriteContract({
    mutation: { onError: (err) => toast.error(txErrorMessage(err)) },
  })
  const { isSuccess: replySuccess } = useWaitForTransactionReceipt({ hash: replyTxHash })

  useEffect(() => {
    if (replySuccess) {
      toast.success('Reply posted!'); setNewComment(''); setReplyOpen(false); refetch(); refetchRegisteredBatch()
    }
  }, [replySuccess, refetch, refetchRegisteredBatch])

  const submitReply = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!newComment || !batchId) return
    setUploading(true)
    try {
      toast('Uploading reply...')
      const { reference } = await writer.uploadData(batchId, newComment)
      writeReply({
        address: PINKCHAINSAW_ADDRESS,
        abi: PINKCHAINSAW_ABI,
        functionName: 'createComment',
        args: [commentId as `0x${string}`, `0x${reference}`, `0x${batchId}`],
      })
    } catch (err) {
      toast.error(`Reply failed: ${txErrorMessage(err)}`)
    } finally {
      setUploading(false)
    }
  }

  if (!post) return null

  const subCommentIds = post.commentIds as string[] || []
  const rating = Number(post.rating)
  const timestamp = Number(post.timestamp) * 1000
  const owner = post.owner as string

  return (
    <div className={depth > 0 ? 'ml-4 border-l border-dashed border-[#252525] pl-4' : ''}>
      <div className="mb-4">
        {/* Comment body */}
        <p className="text-sm text-[#f2f5f4] whitespace-pre-wrap max-w-[532px] break-words">{commentText}</p>

        {/* Comment footer */}
        <div className="flex items-center gap-3 mt-1 pb-2 border-b border-[#252525] text-xs text-[#888]">
          <button
            onClick={() => handleVote('upVote')}
            disabled={!canWrite || votePending || castVote === 1}
            title={castVote === 1 ? 'already upvoted' : 'upvote'}
            className={castVote === 1 ? 'text-[#e84393]' : canWrite && !votePending ? 'hover:text-[#e84393] cursor-pointer' : 'text-[#444] cursor-not-allowed'}
          >
            +
          </button>
          <button
            onClick={() => handleVote('downVote')}
            disabled={!canWrite || votePending || castVote === -1}
            title={castVote === -1 ? 'already downvoted' : 'downvote'}
            className={castVote === -1 ? 'text-[#f2f5f4]' : canWrite && !votePending ? 'hover:text-[#f2f5f4] cursor-pointer' : 'text-[#444] cursor-not-allowed'}
          >
            -
          </button>
          <span className={rating > 0 ? 'text-[#e84393]' : rating < 0 ? 'text-[#f2f5f4]' : ''}>{rating}</span>
          <EnsName address={owner} className="font-mono truncate max-w-[100px]" />
          <span>
            {new Date(timestamp).toLocaleDateString('en-GB', {
              year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
            })}
          </span>
          <button onClick={() => setReplyOpen(!replyOpen)} disabled={!canWrite} className={canWrite ? 'hover:text-[#e84393] cursor-pointer' : 'text-[#444] cursor-not-allowed'}>
            reply
          </button>
        </div>

        {/* Reply form */}
        {replyOpen && (
          <form onSubmit={submitReply} className="mt-2 mb-2">
            <textarea
              className="w-full max-w-[532px] bg-[#1b1e1f] text-[#f2f5f4] border border-[#252525] rounded p-2 text-sm resize-y min-h-[50px] focus:border-[#e84393] focus:outline-none"
              value={newComment}
              onChange={e => setNewComment(e.target.value)}
              placeholder="reply..."
            />
            <button type="submit" disabled={uploading || replyPending} className={`mt-1 px-3 py-1 bg-[#e84393] text-white text-xs rounded ${uploading || replyPending ? 'opacity-50 cursor-not-allowed' : 'hover:brightness-110'}`}>
              {uploading || replyPending ? 'Posting...' : 'Reply'}
            </button>
          </form>
        )}

        {/* Nested comments */}
        {depth >= MAX_DEPTH ? (
          subCommentIds.length > 0 && (
            <p className="text-xs text-[#888]">
              {subCommentIds.length} deeper repl{subCommentIds.length === 1 ? 'y' : 'ies'} not shown
            </p>
          )
        ) : (
          subCommentIds.map((id: string) => (
            <CommentItem commentId={id} key={id} depth={depth + 1} />
          ))
        )}
      </div>
    </div>
  )
}

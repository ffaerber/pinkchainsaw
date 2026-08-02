import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router'
import { useAccount, useReadContract, useWatchContractEvent, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import toast from 'react-hot-toast'
import { PINKCHAINSAW_ABI, PINKCHAINSAW_ADDRESS, BZZ_TOKEN_ADDRESS, ERC20_ABI } from '../config/contracts'
import { useBeeContext } from '../hooks/BeeContext'
import { usePostingBatch } from '../hooks/usePostingBatch'
import { txErrorMessage } from '../lib/errors'
import CommentItem from './CommentItem'
import EnsName from './EnsName'

export default function ThreadDetails() {
  const { threadId } = useParams<{ threadId: string }>()
  const { address } = useAccount()
  const { writer, readUrl } = useBeeContext()
  const { postingBatchId: batchId, refetchRegisteredBatch } = usePostingBatch()

  const { data: bzzAllowance } = useReadContract({
    address: BZZ_TOKEN_ADDRESS, abi: ERC20_ABI, functionName: 'allowance',
    args: address ? [address, PINKCHAINSAW_ADDRESS] : undefined, query: { enabled: !!address },
  })
  const canWrite = !!address && !!batchId && bzzAllowance && (bzzAllowance as bigint) > 0n

  const { data: thread, refetch } = useReadContract({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    functionName: 'getThread',
    args: threadId ? [threadId as `0x${string}`] : undefined,
    query: { enabled: !!threadId },
  })

  const post = thread as any
  const bzzhash = post?.bzzhash ? (post.bzzhash as string).replace('0x', '') : ''
  const imgSrc = bzzhash ? `${readUrl}/bzz/${bzzhash}` : ''

  // The vote this account has already cast: 1, -1, or 0
  const { data: myVote, refetch: refetchVote } = useReadContract({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    functionName: 'getVote',
    args: threadId && address ? [threadId as `0x${string}`, address] : undefined,
    query: { enabled: !!threadId && !!address },
  })
  const castVote = Number(myVote ?? 0)

  // Refresh when anyone votes or comments on this thread
  useWatchContractEvent({
    address: PINKCHAINSAW_ADDRESS,
    abi: PINKCHAINSAW_ABI,
    eventName: 'ThreadUpdated',
    onLogs(logs) {
      if (logs.some(log => (log as any).args?.id === threadId)) refetch()
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
    if (!threadId) return
    writeVote({
      address: PINKCHAINSAW_ADDRESS,
      abi: PINKCHAINSAW_ABI,
      functionName: fn,
      args: [threadId as `0x${string}`],
    })
  }

  // Comment
  const [newComment, setNewComment] = useState('')
  const [uploading, setUploading] = useState(false)
  const { writeContract: writeComment, data: commentTxHash, isPending: commentPending } = useWriteContract({
    mutation: { onError: (err) => toast.error(txErrorMessage(err)) },
  })
  const { isSuccess: commentSuccess } = useWaitForTransactionReceipt({ hash: commentTxHash })

  useEffect(() => {
    if (commentSuccess) { toast.success('Comment posted!'); setNewComment(''); refetch(); refetchRegisteredBatch() }
  }, [commentSuccess, refetch, refetchRegisteredBatch])

  const submitComment = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!threadId || !newComment || !batchId) return
    setUploading(true)
    try {
      toast('Uploading comment...')
      const { reference } = await writer.uploadData(batchId, newComment)
      writeComment({
        address: PINKCHAINSAW_ADDRESS,
        abi: PINKCHAINSAW_ABI,
        functionName: 'createComment',
        args: [threadId as `0x${string}`, `0x${reference}`, `0x${batchId}`],
      })
    } catch (err) {
      toast.error(`Comment failed: ${txErrorMessage(err)}`)
    } finally {
      setUploading(false)
    }
  }

  if (!post) return <div className="text-center text-[#888] mt-20">Loading...</div>

  const commentIds = post.commentIds as string[] || []
  const timestamp = Number(post.timestamp) * 1000
  const rating = Number(post.rating)
  const owner = post.owner as string

  return (
    <div className="max-w-[900px] mx-auto">
      {/* Image */}
      <div className="bg-black flex justify-center">
        <img className="max-w-full max-h-[80vh]" src={imgSrc} alt="" />
      </div>

      {/* Vote + Info bar */}
      <div className="flex items-start gap-4 px-4 py-3 border-b border-[#252525]">
        {/* Votes */}
        <div className="flex items-center gap-1">
          <button
            onClick={() => handleVote('upVote')}
            disabled={!canWrite || votePending || castVote === 1}
            title={castVote === 1 ? 'already upvoted' : 'upvote'}
            className={`text-xl leading-none ${castVote === 1 ? 'text-[#e84393]' : canWrite && !votePending ? 'text-[#888] hover:text-[#e84393] cursor-pointer' : 'text-[#444] cursor-not-allowed'}`}
          >
            +
          </button>
          <span className="text-[42px] font-light text-[#f2f5f4] leading-none px-2">{rating}</span>
          <button
            onClick={() => handleVote('downVote')}
            disabled={!canWrite || votePending || castVote === -1}
            title={castVote === -1 ? 'already downvoted' : 'downvote'}
            className={`text-xl leading-none ${castVote === -1 ? 'text-[#f2f5f4]' : canWrite && !votePending ? 'text-[#888] hover:text-[#f2f5f4] cursor-pointer' : 'text-[#444] cursor-not-allowed'}`}
          >
            -
          </button>
        </div>

        <div className="flex-1" />

        {/* Meta */}
        <div className="text-xs text-[#888] text-right">
          <EnsName address={owner} className="font-mono truncate max-w-[200px]" />
          <p>
            {new Date(timestamp).toLocaleDateString('en-GB', {
              year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
            })}
          </p>
        </div>
      </div>

      {/* Comment form */}
      <form onSubmit={submitComment} className="px-4 py-3 border-b border-[#252525]">
        <textarea
          className={`w-full bg-[#1b1e1f] text-[#f2f5f4] border border-[#252525] rounded p-2 text-sm resize-y min-h-[60px] focus:border-[#e84393] focus:outline-none ${!canWrite ? 'opacity-50 cursor-not-allowed' : ''}`}
          value={newComment}
          onChange={e => setNewComment(e.target.value)}
          placeholder={canWrite ? 'write a comment...' : 'connect & approve to comment...'}
          disabled={!canWrite}
        />
        <button type="submit" disabled={!canWrite || uploading || commentPending} className={`mt-2 px-4 py-1.5 bg-[#e84393] text-white text-sm rounded ${canWrite && !uploading && !commentPending ? 'hover:brightness-110' : 'opacity-50 cursor-not-allowed'}`}>
          {uploading || commentPending ? 'Posting...' : 'Comment'}
        </button>
      </form>

      {/* Comments */}
      <div className="px-4 py-3">
        {commentIds.length > 0 && (
          <p className="text-xs text-[#888] mb-3">{commentIds.length} comment{commentIds.length !== 1 ? 's' : ''}</p>
        )}
        {commentIds.map((commentId: string) => (
          <CommentItem commentId={commentId} key={commentId} depth={0} />
        ))}
      </div>

      {/* Back link */}
      <div className="px-4 py-6">
        <Link to="/" className="text-sm text-[#888] hover:text-[#e84393]">back</Link>
      </div>
    </div>
  )
}

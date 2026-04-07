import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router'
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import toast from 'react-hot-toast'
import { PINKCHAINSAW_ABI, PINKCHAINSAW_ADDRESS, BZZ_TOKEN_ADDRESS, ERC20_ABI } from '../config/contracts'
import { useBeeContext } from '../hooks/BeeContext'
import CommentItem from './CommentItem'
import EnsName from './EnsName'

export default function ThreadDetails() {
  const { threadId } = useParams<{ threadId: string }>()
  const { address } = useAccount()
  const { writer, readUrl, batchId } = useBeeContext()

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

  // Voting
  const { writeContract: writeVote, data: voteTxHash } = useWriteContract()
  const { isSuccess: voteSuccess } = useWaitForTransactionReceipt({ hash: voteTxHash })

  useEffect(() => {
    if (voteSuccess) { toast.success('Vote recorded!'); refetch() }
  }, [voteSuccess, refetch])

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
  const { writeContract: writeComment, data: commentTxHash } = useWriteContract()
  const { isSuccess: commentSuccess } = useWaitForTransactionReceipt({ hash: commentTxHash })

  useEffect(() => {
    if (commentSuccess) { toast.success('Comment posted!'); setNewComment(''); refetch() }
  }, [commentSuccess, refetch])

  const submitComment = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!threadId || !newComment || !batchId) return
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
      toast.error(`Comment failed: ${err}`)
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
          <button onClick={() => handleVote('upVote')} disabled={!canWrite} className={`text-xl leading-none ${canWrite ? 'text-[#888] hover:text-[#e84393] cursor-pointer' : 'text-[#444] cursor-not-allowed'}`}>+</button>
          <span className="text-[42px] font-light text-[#f2f5f4] leading-none px-2">{rating}</span>
          <button onClick={() => handleVote('downVote')} disabled={!canWrite} className={`text-xl leading-none ${canWrite ? 'text-[#888] hover:text-[#f2f5f4] cursor-pointer' : 'text-[#444] cursor-not-allowed'}`}>-</button>
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
        <button type="submit" disabled={!canWrite} className={`mt-2 px-4 py-1.5 bg-[#e84393] text-white text-sm rounded ${canWrite ? 'hover:brightness-110' : 'opacity-50 cursor-not-allowed'}`}>
          Comment
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

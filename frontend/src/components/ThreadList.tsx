import { useThreads } from '../hooks/ThreadsContext'
import ThreadTile from './ThreadTile'
import UploadTile from './UploadTile'

export default function ThreadList() {
  // Loaded once in ThreadsProvider, so the thread page can page through the
  // same list. Expired posts hide their own tiles; `expired` is only so the
  // page can say so, because a grid that silently shrinks reads as a bug in
  // the app rather than as content that stopped being paid for.
  const { ids: allThreadIds, allLoaded, error: totalThreadsError, expired, reportStatus: handleTileStatus } = useThreads()

  if (totalThreadsError) {
    return (
      <p className="text-center text-[#888] mt-20 text-sm">
        Could not reach the contract. Check your network connection and reload.
      </p>
    )
  }

  return (
    <div className="flex flex-wrap gap-1 p-1 justify-center">
      <UploadTile />
      {allThreadIds.map(threadId => (
        <ThreadTile threadId={threadId} key={threadId} onStatus={handleTileStatus} />
      ))}
      {!allLoaded && (
        <div className="w-[128px] h-[128px] bg-[#212121] animate-pulse" />
      )}
      {allLoaded && expired.size > 0 && (
        <p className="w-full text-center text-xs text-[#666] py-6">
          {expired.size === allThreadIds.length
            ? 'Every post here has expired from Swarm — their postage stamps ran out and the network dropped the images. Post something to start it off again.'
            : `${expired.size} ${expired.size === 1 ? 'post is' : 'posts are'} hidden: their postage stamps expired and the images are no longer on Swarm.`}
        </p>
      )}
    </div>
  )
}

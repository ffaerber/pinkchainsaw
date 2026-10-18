/**
 * One line that says what this is, with the details folded away so the grid
 * stays the first thing people see. Wording follows the README's model:
 * engagement funds the storage of the content being engaged with.
 */
export default function About() {
  return (
    // basis-full: its own line in the grid's flex-wrap, so it never shares a
    // row with tiles (which would also shift the inline post panel's row).
    <div className="basis-full flex justify-center">
    <details className="w-full max-w-[680px] px-3 py-2 text-xs text-[#888] group">
      <summary className="cursor-pointer list-none text-center select-none">
        <span className="text-[#bbb]">A decentralized imageboard</span>
        {' '}— no central server and no sign-up.{' '}
        <span className="text-[#e84393] group-open:hidden">How it works ▸</span>
        <span className="text-[#e84393] hidden group-open:inline">close ▾</span>
      </summary>
      <ul className="mt-3 space-y-1.5 leading-relaxed list-disc pl-5">
        <li>
          <span className="text-[#bbb]">Images and comments</span> are stored on{' '}
          <a href="https://www.ethswarm.org" target="_blank" rel="noreferrer" className="underline hover:text-[#e84393]">Swarm</a>,
          a peer-to-peer storage network. <span className="text-[#bbb]">Posts and votes</span> live in a
          smart contract on Gnosis Chain, and this site itself is served from Swarm via the ENS name pinkchainsaw.eth.
        </li>
        <li>
          <span className="text-[#bbb]">Browsing is free</span> and needs nothing. To post, comment or vote you
          connect a wallet and a Bee (Swarm) node.
        </li>
        <li>
          Each action costs a small <span className="text-[#bbb]">xBZZ fee</span>, plus gas in xDAI. Replies and votes
          pay for the storage of the post they go to — so engagement is what keeps a post alive. A new post's fee
          keeps this site itself hosted.
        </li>
        <li>
          Storage is rented, not owned: when nobody pays for a post anymore, its image disappears from Swarm.
          The post itself stays on chain forever.
        </li>
        <li>
          Posting gets cheaper for authors whose posts are well received, and more expensive for those whose aren't.
        </li>
      </ul>
    </details>
    </div>
  )
}

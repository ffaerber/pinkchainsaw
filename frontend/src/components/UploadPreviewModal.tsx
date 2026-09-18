import { useEffect, useState } from 'react'
import { prepareImage, formatBytes, type PreparedImage } from '../lib/image'

/**
 * Sits between picking a file and uploading it. Two reasons it exists: an
 * upload to Swarm is permanent and public, so the last look belongs before the
 * bytes leave; and the image is re-encoded on the way through, which is worth
 * showing rather than doing silently.
 */
export default function UploadPreviewModal({
  file,
  uploading,
  onCancel,
  onConfirm,
}: {
  file: File
  uploading: boolean
  onCancel: () => void
  onConfirm: (prepared: File) => void
}) {
  const [prepared, setPrepared] = useState<PreparedImage | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let url: string | undefined
    let cancelled = false
    setPrepared(null)
    setError(null)
    prepareImage(file)
      .then(p => {
        if (cancelled) { URL.revokeObjectURL(p.previewUrl); return }
        url = p.previewUrl
        setPrepared(p)
      })
      .catch(e => { if (!cancelled) setError(e?.message ?? String(e)) })
    // The object URL is the one thing here that leaks if it is not released:
    // it pins the whole blob in memory until the document goes away.
    return () => { cancelled = true; if (url) URL.revokeObjectURL(url) }
  }, [file])

  // Escape closes, as in any other dialog. Not while uploading: the bytes are
  // already on their way and closing would only hide what is happening.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape' && !uploading) onCancel() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [uploading, onCancel])

  const saved = prepared && prepared.originalBytes > 0
    ? Math.round((1 - prepared.bytes / prepared.originalBytes) * 100)
    : 0

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/90 p-4"
      onClick={() => { if (!uploading) onCancel() }}
    >
      <div
        className="bg-[#1b1e1f] border border-[#252525] rounded-lg p-5 w-full max-w-md"
        onClick={e => e.stopPropagation()}
      >
        <h2 className="text-sm font-medium text-[#f2f5f4] mb-3">Upload to Swarm</h2>

        {error && <p className="text-sm text-[#e84393] mb-3">Could not read that image: {error}</p>}

        {!prepared && !error && (
          <div className="h-48 flex items-center justify-center text-sm text-[#888]">preparing…</div>
        )}

        {prepared && (
          <>
            <img
              src={prepared.previewUrl}
              alt={prepared.file.name}
              className="w-full max-h-72 object-contain rounded bg-black/40 mb-3"
            />
            <dl className="text-xs text-[#888] space-y-1 mb-4">
              <div className="flex justify-between gap-4">
                <dt>File</dt>
                <dd className="text-[#f2f5f4] truncate">{prepared.file.name}</dd>
              </div>
              {prepared.width > 0 && (
                <div className="flex justify-between gap-4">
                  <dt>Dimensions</dt>
                  <dd className="text-[#f2f5f4]">{prepared.width} × {prepared.height}</dd>
                </div>
              )}
              <div className="flex justify-between gap-4">
                <dt>Size</dt>
                <dd className="text-[#f2f5f4]">
                  {prepared.converted ? (
                    <>
                      {formatBytes(prepared.originalBytes)} → {formatBytes(prepared.bytes)}
                      {saved > 0 && <span className="text-[#e84393]"> ({saved}% smaller)</span>}
                    </>
                  ) : formatBytes(prepared.bytes)}
                </dd>
              </div>
            </dl>

            <p className="text-xs text-[#666] mb-4">
              {prepared.converted
                ? 'Converted to WebP. Camera, timestamp and GPS metadata are not carried over.'
                : 'Uploaded as-is: converting an animated GIF would flatten it to a single frame.'}
            </p>
          </>
        )}

        <div className="flex justify-end gap-2">
          <button
            onClick={onCancel}
            disabled={uploading}
            className="px-3 py-1.5 text-sm border border-[#333] text-[#888] rounded cursor-pointer hover:border-[#555] hover:text-[#f2f5f4] disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Cancel
          </button>
          <button
            onClick={() => prepared && onConfirm(prepared.file)}
            disabled={!prepared || uploading}
            className="px-4 py-1.5 text-sm bg-[#e84393] text-white rounded cursor-pointer hover:brightness-110 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {uploading ? 'Uploading…' : 'Upload'}
          </button>
        </div>
      </div>
    </div>
  )
}

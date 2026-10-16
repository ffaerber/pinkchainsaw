/**
 * Prepare a picked image for upload: shrink it, re-encode it as WebP, and drop
 * everything that is not pixels.
 *
 * Stripping metadata is not a separate step here, it is a consequence of the
 * encode. A canvas holds pixels and nothing else, so EXIF — camera, lens,
 * timestamps, and the GPS coordinates a phone writes by default — cannot
 * survive the round trip. That matters on an image board where posts are
 * public and permanent: a postage batch keeps a chunk alive for as long as it
 * is paid for, and there is no edit later.
 *
 * Orientation is the one piece of EXIF that must be honoured before it is
 * discarded, or portrait photos from a phone upload sideways. createImageBitmap
 * with imageOrientation: 'from-image' applies the rotation to the pixels, which
 * is exactly the trade we want: the effect is kept, the tag is not.
 */

/**
 * Pixel budget of the uploaded image: 1600 × 1600. Capped by area, not by the
 * longest edge — an edge cap squeezes long strips (comics, tall memes) to a
 * sliver: 308 × 6400 became 77 × 1600, unreadable. By area, a 2 MP strip
 * keeps every pixel while a 12 MP phone photo still comes down to ~1850 × 1390.
 */
export const MAX_PIXELS = 1600 * 1600
/** WebP cannot encode an edge longer than this. */
const WEBP_MAX_EDGE = 16383
/** WebP quality. 0.82 is where artefacts stop being visible on photos. */
export const WEBP_QUALITY = 0.82

export interface PreparedImage {
  /** The bytes to upload. */
  file: File
  /** Object URL for previewing; revoke it when the preview closes. */
  previewUrl: string
  width: number
  height: number
  originalBytes: number
  bytes: number
  /** False when the original is passed through untouched (see below). */
  converted: boolean
}

/**
 * Animated GIFs are passed through unchanged. A canvas can only hold one frame,
 * so converting one here would silently turn an animation into a still — a
 * worse outcome than the metadata it would strip, and GIFs carry no EXIF to
 * begin with.
 */
const PASSTHROUGH = new Set(['image/gif'])

export async function prepareImage(
  file: File,
  { maxPixels = MAX_PIXELS, quality = WEBP_QUALITY }: { maxPixels?: number; quality?: number } = {},
): Promise<PreparedImage> {
  if (PASSTHROUGH.has(file.type)) {
    const bitmap = await createImageBitmap(file).catch(() => null)
    const prepared: PreparedImage = {
      file,
      previewUrl: URL.createObjectURL(file),
      width: bitmap?.width ?? 0,
      height: bitmap?.height ?? 0,
      originalBytes: file.size,
      bytes: file.size,
      converted: false,
    }
    bitmap?.close()
    return prepared
  }

  const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' })
  const scale = Math.min(
    1,
    Math.sqrt(maxPixels / (bitmap.width * bitmap.height)),
    WEBP_MAX_EDGE / Math.max(bitmap.width, bitmap.height),
  )
  const width = Math.max(1, Math.round(bitmap.width * scale))
  const height = Math.max(1, Math.round(bitmap.height * scale))

  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('canvas 2d context unavailable')
  ctx.drawImage(bitmap, 0, 0, width, height)
  bitmap.close()

  const blob = await new Promise<Blob | null>(resolve =>
    canvas.toBlob(resolve, 'image/webp', quality))
  if (!blob) throw new Error('could not encode the image as WebP')

  const name = file.name.replace(/\.[^.]+$/, '') + '.webp'
  const webp = new File([blob], name, { type: 'image/webp' })

  return {
    file: webp,
    previewUrl: URL.createObjectURL(webp),
    width,
    height,
    originalBytes: file.size,
    bytes: webp.size,
    converted: true,
  }
}

export function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`
  return `${(n / 1024 / 1024).toFixed(1)} MB`
}

/**
 * Host half of the video-analysis sidebar entry.
 *
 * Registers a same-origin POST route `/dsh-sidebar-entry/analyze` that the
 * Client half calls with either a raw video file body (upload) or a JSON
 * `{ videoPath }` (disk file). It extracts 1 fps frames with ffmpeg, stores
 * them as image attachments, picks a vision-capable model, then streams
 * overlapping frame-sequence windows through `llm.stream` to produce
 * multi-frame, temporally-aware descriptions of the sequence.
 */
import { execFile } from 'node:child_process'
import { mkdtemp, mkdir, writeFile, readFile, readdir, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { promisify } from 'node:util'

const execFileAsync = promisify(execFile)

const ROUTE_PATH = '/dsh-sidebar-entry/analyze'
const MAX_BODY_BYTES = 512 * 1024 * 1024

export const inject = ['webServer', 'llm', 'attachments']

function clamp(value, min, max, fallback) {
  const n = Number(value)
  if (!Number.isFinite(n)) return fallback
  return Math.min(max, Math.max(min, n))
}

function clampInt(value, min, max, fallback) {
  return Math.round(clamp(value, min, max, fallback))
}

function sendJson(res, status, body) {
  const data = JSON.stringify(body)
  res.statusCode = status
  res.setHeader('content-type', 'application/json; charset=utf-8')
  res.setHeader('content-length', Buffer.byteLength(data))
  res.end(data)
}

async function readBody(req, maxBytes = MAX_BODY_BYTES) {
  const chunks = []
  let total = 0
  for await (const chunk of req) {
    total += chunk.length
    if (total > maxBytes) {
      throw Object.assign(new Error('Upload exceeds the 512 MB limit'), { code: 'too-large' })
    }
    chunks.push(chunk)
  }
  return Buffer.concat(chunks)
}

function extensionOf(name) {
  const ext = path.extname(String(name || '')).toLowerCase()
  return /^\.[a-z0-9]{1,5}$/.test(ext) ? ext : '.mp4'
}

async function extractFrames(videoPath, framesDir, fps) {
  const vf = `fps=${fps},scale=w='min(1024\\,iw)':h='min(1024\\,ih)':force_original_aspect_ratio=decrease`
  await execFileAsync('ffmpeg', [
    '-y', '-hide_banner', '-loglevel', 'error',
    '-i', videoPath,
    '-vf', vf,
    path.join(framesDir, 'frame_%04d.jpg'),
  ])
}

async function detectVisionModel(ctx) {
  const llm = ctx.llm
  const isVision = async (provider, model) => {
    try {
      const info = await llm.resolveModelInfo(provider, model)
      return (info.inputModalities ?? []).includes('image')
    } catch {
      return false
    }
  }

  // Prefer the session's current selection when it already accepts images.
  const current = ctx.get('agentDefaultModel')?.currentSelection?.()
  if (current?.provider && current?.model && await isVision(current.provider, current.model)) {
    return { provider: current.provider, model: current.model }
  }

  // Otherwise scan every registered provider for a vision-capable model.
  const providers = await llm.listProviders()
  for (const provider of providers) {
    let models
    try {
      models = await llm.listModels(provider.id)
    } catch {
      continue
    }
    for (const model of models) {
      if ((model.inputModalities ?? []).includes('image')) {
        return { provider: provider.id, model: model.id }
      }
    }
  }
  return null
}

async function describeWindow(ctx, model, frameRefs, { fps, start, end, maxTokens }) {
  const system =
    'You analyze a sequence of video frames sampled at a fixed rate. Treat the frames as ONE continuous '
    + 'sequence and describe what happens across them: motion, actions, subject and camera changes, and how '
    + 'the scene develops over time. Never describe frames in isolation; give one coherent, temporally-aware '
    + 'description of the whole sequence. Be concrete and factual.'

  const userText =
    `Frames ${start + 1} through ${end} of the sequence `
    + `(t = ${(start / fps).toFixed(1)}s to ${((end - 1) / fps).toFixed(1)}s). Describe this sequence:`

  const messages = [{
    role: 'user',
    content: [
      { type: 'text', text: userText },
      ...frameRefs.map(attachment => ({ type: 'image', attachment })),
    ],
  }]

  // Bounded retry for transient transport/server failures: the Files upload is
  // cached, so a retry reuses the uploaded file ids without re-uploading frames.
  const retryable = new Set(['TRANSPORT', 'SERVER', 'RATE_LIMIT', 'TIMEOUT'])
  let lastFailure
  for (let attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) await new Promise(resolve => setTimeout(resolve, 1200 * attempt))
    const parts = []
    try {
      for await (const chunk of ctx.llm.stream({
        provider: model.provider,
        model: model.model,
        system,
        messages,
        maxTokens,
      })) {
        if (chunk.type === 'text-delta') parts.push(chunk.text)
        else if (chunk.type === 'finish' && (chunk.reason.kind === 'error' || chunk.reason.kind === 'aborted')) {
          const failure = chunk.reason.failure
          const detail = [
            failure?.code,
            failure?.status === undefined ? undefined : `HTTP ${failure.status}`,
            failure?.message,
          ].filter(Boolean).join(' — ')
          throw Object.assign(
            new Error(detail || `model call ${chunk.reason.kind}`),
            { code: failure?.code ?? 'model-error' },
          )
        }
      }
      const text = parts.join('').trim()
      if (text.length === 0) {
        throw Object.assign(new Error('The model returned an empty description'), { code: 'EMPTY_RESPONSE' })
      }
      return text
    } catch (error) {
      lastFailure = error
      if (retryable.has(error?.code) && attempt < 2) continue
      throw error
    }
  }
  throw lastFailure
}

async function analyze(ctx, { videoPath, videoBuffer, filename, options }) {
  const fps = clamp(options.fps, 0.1, 30, 1)
  const windowSize = clampInt(options.window, 1, 20, 6)
  const stride = clampInt(options.stride, 1, 20, 4)
  const maxFrames = clampInt(options.maxFrames, 1, 600, 120)
  const maxTokens = clampInt(options.maxTokens, 64, 8000, 600)

  const workDir = await mkdtemp(path.join(tmpdir(), 'dsh-video-'))
  try {
    let inputPath
    if (videoBuffer) {
      inputPath = path.join(workDir, `input${extensionOf(filename)}`)
      await writeFile(inputPath, videoBuffer)
    } else {
      inputPath = path.resolve(videoPath)
    }

    const framesDir = path.join(workDir, 'frames')
    await mkdir(framesDir, { recursive: true })
    await extractFrames(inputPath, framesDir, fps)

    let frameFiles = (await readdir(framesDir)).filter(name => /\.jpe?g$/i.test(name)).sort()
    if (frameFiles.length === 0) {
      throw Object.assign(new Error('No frames extracted — is this a readable video file?'), { code: 'no-frames' })
    }
    if (frameFiles.length > maxFrames) frameFiles = frameFiles.slice(0, maxFrames)

    // Save one image at a time: `saveImages` enforces the deployment's per-message
    // image-count limit on the whole batch, while `saveImage` validates each frame
    // individually (byte/pixel/type only). Each model window stays far under the
    // provider's 600-images-per-request budget.
    const refs = []
    for (const name of frameFiles) {
      refs.push(await ctx.attachments.saveImage({
        data: await readFile(path.join(framesDir, name)),
        mediaType: 'image/jpeg',
        name,
      }))
    }

    const model = await detectVisionModel(ctx)
    if (model === null) {
      throw Object.assign(
        new Error('No vision-capable model is configured. Add a provider/model whose inputModalities include image.'),
        { code: 'no-vision-model' },
      )
    }

    const windows = []
    for (let start = 0; start < refs.length; start += stride) {
      const end = Math.min(start + windowSize, refs.length)
      const text = await describeWindow(ctx, model, refs.slice(start, end), { fps, start, end, maxTokens })
      windows.push({
        index: windows.length,
        start,
        end: end - 1,
        seconds: [Number((start / fps).toFixed(1)), Number(((end - 1) / fps).toFixed(1))],
        text,
      })
      if (end >= refs.length) break
    }

    return { ok: true, model, frameCount: refs.length, fps: Number(fps), windows }
  } finally {
    await rm(workDir, { recursive: true, force: true }).catch(() => {})
  }
}

function parseOptions(raw) {
  if (typeof raw !== 'string' || raw === '') return {}
  try {
    const parsed = JSON.parse(raw)
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {}
  }
}

export function apply(ctx) {
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: ROUTE_PATH,
    handler: async (req, res) => {
      try {
        const rejection = ctx.get('connection')?.requestRejection?.(req)
        if (rejection !== undefined) {
          res.statusCode = rejection
          res.end()
          return
        }
        if (req.method !== 'POST') {
          sendJson(res, 405, { ok: false, code: 'method', message: 'POST only' })
          return
        }

        const essence = String(req.headers['content-type'] ?? '').split(';', 1)[0].trim().toLowerCase()
        let videoPath = null
        let videoBuffer = null
        const filename = String(req.headers['x-file-name'] ?? '')
        let options = parseOptions(req.headers['x-options'])

        if (essence === 'application/json') {
          const body = JSON.parse((await readBody(req, 1024 * 1024)).toString('utf8'))
          videoPath = body?.videoPath
          options = { ...options, ...(body?.options ?? {}) }
          if (typeof videoPath !== 'string' || videoPath.trim() === '') {
            sendJson(res, 400, { ok: false, code: 'bad-request', message: 'videoPath is required' })
            return
          }
        } else {
          videoBuffer = await readBody(req)
          if (videoBuffer.length === 0) {
            sendJson(res, 400, { ok: false, code: 'empty', message: 'Empty request body' })
            return
          }
        }

        const result = await analyze(ctx, { videoPath, videoBuffer, filename, options })
        sendJson(res, 200, result)
      } catch (error) {
        const status = error?.code === 'too-large' ? 413 : 500
        sendJson(res, status, {
          ok: false,
          code: error?.code ?? 'error',
          message: error?.message ?? String(error),
        })
      }
    },
  }), 'dsh-sidebar-entry: analyze route')
}

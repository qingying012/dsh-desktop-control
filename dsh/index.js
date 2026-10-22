// dsh-desktop-control — DeepSeek Harness plugin
//
// Registers one `desktop` tool that lets the model see the screen and drive
// the mouse/keyboard: screenshot, window list, click, move, drag, scroll,
// type, key, activate, cursor position and wait.
//
// Implementation: every call spawns the bundled `assets/gui.ps1` (Windows
// PowerShell 5.1) and parses its output. Keeping the Win32 work in PowerShell
// avoids a native addon, keeps the package tiny, and reuses the script that
// was already battle-tested on this machine.
//
// Coordinates are physical pixels and match the saved screenshot one-to-one:
// the script enables per-monitor DPI awareness v2 internally.
//
// Safety: this is full desktop control. It can click anything and type
// anything. Every call is a normal tool call, so the host's tool policy and
// the user's judgement are the only gates. Do not enable it on an unattended
// machine.
import { spawn } from 'node:child_process'
import { existsSync, mkdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = 'dsh-desktop-control'

// `tools` is the registry this plugin contributes the `desktop` tool to.
export const inject = ['tools']

const SCRIPT = fileURLToPath(new URL('../assets/gui.ps1', import.meta.url))
const DSH_HOME = process.env.DSH_HOME || join(homedir(), '.dsh')
const SHOT_DIR = join(DSH_HOME, 'desktop-control')

const DEFAULTS = {
  enabled: true,
  // Override only if powershell.exe is not on PATH.
  powershellPath: 'powershell.exe',
  timeoutMs: 30_000,
  // Keep the most recent screenshots in the DSH home so read_image can open them.
  screenshotDir: SHOT_DIR,
}

const ACTIONS = [
  'screenshot',
  'windows',
  'click',
  'move',
  'drag',
  'scroll',
  'type',
  'key',
  'activate',
  'pos',
  'wait',
]

const ACTION_SET = new Set(ACTIONS)

const PARAMETERS = {
  type: 'object',
  additionalProperties: false,
  properties: {
    action: {
      type: 'string',
      enum: ACTIONS,
      description:
        'screenshot (save a PNG and return its path), windows (list visible windows), click, move, drag, scroll, type (paste text), key (press a combo such as ctrl+s), activate (bring a window to front), pos (cursor position), wait.',
    },
    x: { type: 'number', description: 'Target X in physical screen pixels.' },
    y: { type: 'number', description: 'Target Y in physical screen pixels.' },
    x2: { type: 'number', description: 'Drag end X.' },
    y2: { type: 'number', description: 'Drag end Y.' },
    text: { type: 'string', description: 'Text for action=type. Unicode is fine; it is pasted via the clipboard.' },
    key: { type: 'string', description: 'Combo for action=key, e.g. "ctrl+s", "alt+f4", "enter".' },
    window: {
      type: 'string',
      description: 'Window title or process name substring, for screenshot -window or activate.',
    },
    region: {
      type: 'string',
      description: 'Screenshot region "x,y,width,height" in physical pixels.',
    },
    button: { type: 'string', enum: ['left', 'right', 'middle'], description: 'Mouse button for click/drag.' },
    count: { type: 'integer', description: 'Click count, 1-3.' },
    amount: { type: 'integer', description: 'Scroll notches; positive is up. 1 = one wheel notch.' },
    waitMs: { type: 'integer', description: 'Milliseconds for action=wait.' },
    print: {
      type: 'boolean',
      description: 'For screenshot with a window: capture it with PrintWindow even when occluded.',
    },
  },
  required: ['action'],
}

const OUTPUT = {
  type: 'object',
  additionalProperties: false,
  properties: {
    ok: { type: 'boolean' },
    action: { type: 'string' },
    output: { type: 'string' },
    imagePath: { type: 'string' },
    width: { type: 'integer' },
    height: { type: 'integer' },
  },
  required: ['ok', 'action'],
}

function requireNumber(args, key) {
  const value = args[key]
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error(`desktop action "${args.action}" requires a numeric "${key}"`)
  }
  return value
}

function requireString(args, key) {
  const value = args[key]
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`desktop action "${args.action}" requires a non-empty "${key}"`)
  }
  return value
}

function shotPath(config) {
  const dir = config.screenshotDir
  mkdirSync(dir, { recursive: true })
  const d = new Date()
  const pad = (n, w = 2) => String(n).padStart(w, '0')
  const stamp =
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}` +
    `-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}-${pad(d.getMilliseconds(), 3)}`
  return join(dir, `shot-${stamp}.png`)
}

/**
 * Translate one tool call into gui.ps1 argv.
 * Exported for the self-test; not part of the public plugin API.
 */
export function buildArgs(args, config = DEFAULTS) {
  const action = args.action
  if (!ACTION_SET.has(action)) throw new Error(`desktop: unknown action "${action}"`)
  switch (action) {
    case 'screenshot': {
      const path = shotPath(config)
      const argv = ['shot', path]
      if (typeof args.window === 'string' && args.window.length > 0) argv.push('-window', args.window)
      if (typeof args.region === 'string' && args.region.length > 0) argv.push('-region', args.region)
      if (args.print === true) argv.push('-print')
      return { argv, json: true }
    }
    case 'windows':
      return { argv: ['windows'], json: false }
    case 'click': {
      const argv = ['click', requireNumber(args, 'x'), requireNumber(args, 'y')]
      if (args.button !== undefined) argv.push('-button', String(args.button))
      if (args.count !== undefined) argv.push('-count', String(args.count))
      return { argv, json: false }
    }
    case 'move':
      return { argv: ['move', requireNumber(args, 'x'), requireNumber(args, 'y')], json: false }
    case 'drag':
      return {
        argv: [
          'drag',
          requireNumber(args, 'x'),
          requireNumber(args, 'y'),
          requireNumber(args, 'x2'),
          requireNumber(args, 'y2'),
        ],
        json: false,
      }
    case 'scroll': {
      const amount = typeof args.amount === 'number' ? args.amount : 3
      if (typeof args.x === 'number' && typeof args.y === 'number') {
        return { argv: ['scroll', args.x, args.y, amount], json: false }
      }
      return { argv: ['scroll', amount], json: false }
    }
    case 'type':
      // `--` stops option parsing, so text beginning with "-" is safe.
      return { argv: ['type', '--', requireString(args, 'text')], json: false }
    case 'key':
      return { argv: ['key', requireString(args, 'key')], json: false }
    case 'activate':
      return { argv: ['activate', requireString(args, 'window')], json: false }
    case 'pos':
      return { argv: ['pos'], json: false }
    case 'wait': {
      const ms = typeof args.waitMs === 'number' ? args.waitMs : 500
      return { argv: ['wait', ms], json: false }
    }
    default:
      throw new Error(`desktop: unknown action "${action}"`)
  }
}

function runPowerShell(argv, config, signal) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      config.powershellPath,
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', SCRIPT, ...argv.map(String)],
      { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
    )
    let stdout = ''
    let stderr = ''
    let settled = false
    const finish = (error, value) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      signal?.removeEventListener('abort', onAbort)
      if (error) reject(error)
      else resolve(value)
    }
    const onAbort = () => {
      child.kill()
      finish(new Error('desktop: cancelled'))
    }
    const timer = setTimeout(() => {
      child.kill()
      finish(new Error(`desktop: timed out after ${config.timeoutMs} ms`))
    }, config.timeoutMs)
    signal?.addEventListener('abort', onAbort, { once: true })

    child.stdout.setEncoding('utf8')
    child.stderr.setEncoding('utf8')
    child.stdout.on('data', (chunk) => {
      stdout += chunk
    })
    child.stderr.on('data', (chunk) => {
      stderr += chunk
    })
    child.on('error', (error) => finish(error))
    child.on('close', (code) => {
      if (code !== 0) {
        finish(new Error(`desktop: gui.ps1 exited ${code}: ${(stderr || stdout).trim()}`))
        return
      }
      finish(undefined, { stdout: stdout.trim(), stderr: stderr.trim() })
    })
  })
}

export function apply(ctx, userConfig = {}) {
  const config = { ...DEFAULTS, ...(userConfig || {}) }
  if (!config.enabled) return
  if (!existsSync(SCRIPT)) throw new Error(`desktop: bundled script missing at ${SCRIPT}`)

  ctx.tools.register({
    name: 'desktop',
    description:
      'See and control the Windows desktop. action=screenshot saves a PNG and returns its absolute path; open it with read_image to see the screen. Coordinates are physical pixels matching that image. Typical loop: screenshot -> read_image -> click/type -> screenshot again. Supports windows, click, move, drag, scroll, type, key, activate, pos, wait. Use it only when a task truly has no CLI or API path.',
    parameters: PARAMETERS,
    output: {
      schema: OUTPUT,
      render(_args, value) {
        const parts = []
        if (value.imagePath) parts.push(`Screenshot saved: ${value.imagePath}`)
        if (typeof value.width === 'number') parts.push(`Size: ${value.width}x${value.height}`)
        if (value.output) parts.push(value.output)
        return [{ type: 'text', text: parts.join('\n') || 'ok' }]
      },
    },
    isConcurrencySafe: () => false,
    timeoutMs: config.timeoutMs + 5_000,
    async execute(args, exec) {
      const { argv, json } = buildArgs(args, config)
      const { stdout } = await runPowerShell(argv, config, exec?.signal)
      if (json) {
        let parsed
        try {
          parsed = JSON.parse(stdout)
        } catch {
          throw new Error(`desktop: gui.ps1 returned non-JSON for ${args.action}: ${stdout.slice(0, 400)}`)
        }
        return {
          ok: true,
          action: args.action,
          imagePath: typeof parsed.path === 'string' ? parsed.path : undefined,
          width: typeof parsed.width === 'number' ? parsed.width : undefined,
          height: typeof parsed.height === 'number' ? parsed.height : undefined,
          output: stdout,
        }
      }
      return { ok: true, action: args.action, output: stdout }
    },
  })
}

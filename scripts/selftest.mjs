// Pure unit tests for argv construction and argument validation. Nothing here
// touches the real desktop: no screenshots, no mouse, no keyboard.
import assert from 'node:assert/strict'
import { buildArgs } from '../dsh/index.js'

const CFG = {
  screenshotDir: 'C:\\shots',
  screenshotMaxWidth: 1440,
  screenshotGrid: true,
  screenshotCursor: true,
}

// screenshot: absolute .png path + grid + cursor + max-width by default.
{
  const { argv, json } = buildArgs({ action: 'screenshot' }, CFG)
  assert.equal(argv[0], 'shot')
  assert.match(argv[1], /C:\\shots\\shot-\d{8}-\d{6}-\d{3}\.png$/)
  assert.deepEqual(argv.slice(2), ['-grid', '-cursor', '-maxwidth', '1440'])
  assert.equal(json, true)
}

// screenshot: everything can be switched off, and window/region/print still pass through.
{
  const { argv } = buildArgs(
    {
      action: 'screenshot',
      window: '记事本',
      region: '0,0,800,600',
      print: true,
      grid: false,
      cursor: false,
      maxWidth: 0,
    },
    CFG,
  )
  assert.deepEqual(argv.slice(2), ['-window', '记事本', '-region', '0,0,800,600', '-print'])
}

// screenshot: explicit maxWidth overrides the configured default.
{
  const { argv } = buildArgs({ action: 'screenshot', maxWidth: 900 }, CFG)
  assert.equal(argv.at(-1), '900')
  assert.equal(argv.at(-2), '-maxwidth')
}

// elements: no image involved; window/filter/depth/all flags.
{
  assert.deepEqual(buildArgs({ action: 'elements' }).argv, ['elements'])
  assert.deepEqual(buildArgs({ action: 'elements', window: '记事本', filter: '保存', depth: 5 }).argv, [
    'elements',
    '-window',
    '记事本',
    '-filter',
    '保存',
    '-depth',
    '5',
  ])
  assert.deepEqual(buildArgs({ action: 'elements', all: true }).argv, ['elements', '-all'])
}

// ocr: image path is absolutised so gui.ps1 (different cwd) still finds it.
{
  const { argv } = buildArgs({ action: 'ocr', imagePath: 'shot.png' })
  assert.equal(argv[0], 'ocr')
  assert.match(argv[1], /[\\/]shot\.png$/)
  assert.ok(argv[1].includes(':'), 'expected an absolute Windows path')
  assert.deepEqual(buildArgs({ action: 'ocr', imagePath: 'C:\\a\\b.png', filter: '保存' }).argv, [
    'ocr',
    'C:\\a\\b.png',
    '-filter',
    '保存',
  ])
  assert.throws(() => buildArgs({ action: 'ocr' }), /requires a non-empty "imagePath"/)
}

// windows: optional row cap.
{
  assert.deepEqual(buildArgs({ action: 'windows' }).argv, ['windows'])
  assert.deepEqual(buildArgs({ action: 'windows', top: 5 }).argv, ['windows', '-top', '5'])
}

// click: coordinates stay the default path; a uia name switches to control lookup.
{
  assert.deepEqual(buildArgs({ action: 'click', x: 10, y: 20, button: 'right', count: 2 }).argv, [
    'click',
    10,
    20,
    '-button',
    'right',
    '-count',
    '2',
  ])
  assert.throws(() => buildArgs({ action: 'click', x: 10 }), /requires a numeric "y"/)

  const byName = buildArgs({ action: 'click', uia: '保存', window: '记事本', invoke: true })
  assert.deepEqual(byName.argv, ['click', '-uia', '保存', '-window', '记事本', '-invoke'])
  assert.equal(byName.json, true)

  // uia wins over x/y when both are present.
  assert.deepEqual(buildArgs({ action: 'click', uia: '保存', x: 1, y: 2 }).argv, ['click', '-uia', '保存'])
}

// sequence: becomes an ops list for gui.ps1 seq (file is written at execute time).
{
  const { argv, seqOps } = buildArgs({
    action: 'sequence',
    steps: [
      { action: 'click', x: 10, y: 20 },
      { action: 'wait', waitMs: 300, delayMs: 0 },
      { action: 'screenshot', maxWidth: 800, grid: false },
    ],
  })
  assert.equal(argv, null)
  assert.equal(seqOps.length, 3)
  assert.deepEqual(seqOps[0], { cmd: 'click', rest: [10, 20], opt: {}, delayMs: undefined })
  assert.deepEqual(seqOps[1], { cmd: 'wait', rest: [300], opt: {}, delayMs: 0 })
  assert.equal(seqOps[2].cmd, 'shot')
  assert.equal(seqOps[2].opt.maxwidth, '800')
  assert.equal(seqOps[2].opt.grid, undefined)

  assert.throws(() => buildArgs({ action: 'sequence' }), /non-empty "steps"/)
  assert.throws(() => buildArgs({ action: 'sequence', steps: [{ action: 'sequence', steps: [] }] }), /cannot nest/)
}

// type uses `--` so leading dashes are literal text.
{
  const { argv } = buildArgs({ action: 'type', text: '-not-a-flag 中文' })
  assert.deepEqual(argv, ['type', '--', '-not-a-flag 中文'])
}

// scroll has both positional and point forms.
{
  assert.deepEqual(buildArgs({ action: 'scroll', amount: -2 }).argv, ['scroll', -2])
  assert.deepEqual(buildArgs({ action: 'scroll', x: 5, y: 6, amount: 3 }).argv, ['scroll', 5, 6, 3])
}

// move / drag / key / activate / pos / wait.
{
  assert.deepEqual(buildArgs({ action: 'move', x: 1, y: 2 }).argv, ['move', 1, 2])
  assert.deepEqual(buildArgs({ action: 'drag', x: 1, y: 2, x2: 3, y2: 4 }).argv, ['drag', 1, 2, 3, 4])
  assert.deepEqual(buildArgs({ action: 'key', key: 'ctrl+s' }).argv, ['key', 'ctrl+s'])
  assert.deepEqual(buildArgs({ action: 'activate', window: 'DeepSeek' }).argv, ['activate', 'DeepSeek'])
  assert.deepEqual(buildArgs({ action: 'pos' }).argv, ['pos'])
  assert.deepEqual(buildArgs({ action: 'wait' }).argv, ['wait', 500])
}

// unknown action is rejected.
assert.throws(() => buildArgs({ action: 'teleport' }), /unknown action/)

console.log('selftest ok: argv construction and validation behave as expected')

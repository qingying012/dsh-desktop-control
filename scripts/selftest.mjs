// Pure unit tests for argv construction and argument validation. Nothing here
// touches the real desktop: no screenshots, no mouse, no keyboard.
import assert from 'node:assert/strict'
import { buildArgs } from '../dsh/index.js'

// screenshot builds a shot command with an absolute .png path.
{
  const { argv, json } = buildArgs({ action: 'screenshot' }, { screenshotDir: 'C:\\shots' })
  assert.equal(argv[0], 'shot')
  assert.match(argv[1], /C:\\shots\\shot-\d{8}-\d{6}-\d{3}\.png$/)
  assert.equal(json, true)
}

// screenshot with window / region / print adds the right flags.
{
  const { argv } = buildArgs(
    { action: 'screenshot', window: '记事本', region: '0,0,800,600', print: true },
    { screenshotDir: 'C:\\shots' },
  )
  assert.deepEqual(argv.slice(2), ['-window', '记事本', '-region', '0,0,800,600', '-print'])
}

// type uses `--` so leading dashes are literal text.
{
  const { argv } = buildArgs({ action: 'type', text: '-not-a-flag 中文' })
  assert.deepEqual(argv, ['type', '--', '-not-a-flag 中文'])
}

// click validates coordinates and forwards button/count.
{
  const { argv } = buildArgs({ action: 'click', x: 10, y: 20, button: 'right', count: 2 })
  assert.deepEqual(argv, ['click', 10, 20, '-button', 'right', '-count', '2'])
  assert.throws(() => buildArgs({ action: 'click', x: 10 }), /requires a numeric "y"/)
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

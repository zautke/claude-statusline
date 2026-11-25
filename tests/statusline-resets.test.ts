import { expect, mock, test } from 'claude-code/testing'

const USAGE = 'Usage: /statusline-resets [toggle|on|off|clock|countdown|status]'
type Result = { exitCode: number; stdout: string; stderr: string }

// Registers every stub the mod can reach. `answer(argv)` decides each process.run reply:
// a Result resolves, a string rejects the call ({ deny }).
function stubs(on: any, opts: { os?: string; answer?: (argv: string[]) => Result | string; registerDeny?: boolean } = {}) {
  const runs: string[][] = []
  const regs: any[] = []
  on('session.start', () => ({ cwd: '/work' }))
  on('command.register', ($: any, e: any) => {
    regs.push(e)
    return opts.registerDeny ? { deny: 'register refused' } : { value: undefined }
  })
  on('process.run', ($: any, e: any) => {
    runs.push([...e.argv])
    const r = (opts.answer ?? (() => ({ exitCode: 0, stdout: 'Reset times on (clock).\n', stderr: '' })))(e.argv)
    return typeof r === 'string' ? { deny: r } : { value: r }
  })
  mock.env(on, opts.os ? { OS: opts.os } : {})
  return { runs, regs }
}

function flagsOf(argv: string[]) {
  const i = argv.findIndex((a) => /\/scripts\/resets-toggle\.(ps1|sh)$/.test(a))
  return argv.slice(i + 1)
}

async function start($: any) {
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  for (let i = 0; i < 20; i++) await Promise.resolve() // let the un-awaited --sync reach its stub
}

test('session.start registers the exact command spec', async ($, on) => {
  const s = stubs(on, { os: 'Windows_NT' })
  await start($)
  expect(s.regs.length).toBe(1)
  expect(s.regs[0]).toMatchObject({
    name: 'statusline-resets',
    argumentHint: '[toggle|on|off|clock|countdown|status]',
    immediate: true,
  })
  expect(typeof s.regs[0].description).toBe('string')
  expect(s.regs[0].description.length > 0).toBe(true)
})

test('session.start fires --sync through pwsh on Windows', async ($, on) => {
  const s = stubs(on, { os: 'Windows_NT' })
  await start($)
  expect(s.runs.length).toBe(1)
  const argv = s.runs[0]
  expect(argv.slice(0, 4)).toEqual(['pwsh', '-NoProfile', '-NonInteractive', '-File'])
  expect(argv[4]).toMatch(/\/scripts\/resets-toggle\.ps1$/)
  expect(argv.slice(5)).toEqual(['--sync'])
})

test('session.start fires --sync through bash when OS is unset', async ($, on) => {
  const s = stubs(on)
  await start($)
  expect(s.runs.length).toBe(1)
  const argv = s.runs[0]
  expect(argv[0]).toBe('bash')
  expect(argv[1]).toMatch(/\/scripts\/resets-toggle\.sh$/)
  expect(argv.slice(2)).toEqual(['--sync'])
})

test('a rejected --sync does not stop registration', async ($, on) => {
  const s = stubs(on, { os: 'Windows_NT', answer: () => 'sync exploded' })
  await start($)
  expect(s.runs.length).toBe(1)
  expect(s.regs.length).toBe(1)
  expect(s.regs[0].name).toBe('statusline-resets')
})

test('a refused command.register does not break session.start', async ($, on) => {
  const s = stubs(on, { os: 'Windows_NT', registerDeny: true })
  await start($)
  expect(s.regs.length).toBe(1)
})

const MAP: [string, string[]][] = [
  ['', ['--set', 'toggle']],
  ['toggle', ['--set', 'toggle']],
  ['on', ['--set', 'on']],
  ['off', ['--set', 'off']],
  ['clock', ['--format', 'clock']],
  ['countdown', ['--format', 'countdown']],
  ['status', ['--get']],
  ['  OFF  ', ['--set', 'off']],
  ['CountDown', ['--format', 'countdown']],
]

for (const [args, flags] of MAP) {
  test(`args ${JSON.stringify(args)} -> ${flags.join(' ')} (Windows)`, async ($, on) => {
    const s = stubs(on, { os: 'Windows_NT' })
    const answer = await $.command.run({ command: 'statusline-resets', args })
    expect(answer.text).toBe('Reset times on (clock).')
    expect(s.runs.length).toBe(1)
    expect(s.runs[0].slice(0, 4)).toEqual(['pwsh', '-NoProfile', '-NonInteractive', '-File'])
    expect(flagsOf(s.runs[0])).toEqual(flags)
  })
}

test('args map to bash argv off Windows', async ($, on) => {
  const s = stubs(on)
  await $.command.run({ command: 'statusline-resets', args: 'countdown' })
  expect(s.runs[0][0]).toBe('bash')
  expect(s.runs[0][1]).toMatch(/\/scripts\/resets-toggle\.sh$/)
  expect(s.runs[0].slice(2)).toEqual(['--format', 'countdown'])
})

for (const bad of ['bogus', 'on off', 'constructor', '--set']) {
  test(`unknown args ${JSON.stringify(bad)} -> usage, no process`, async ($, on) => {
    const s = stubs(on, { os: 'Windows_NT' })
    const answer = await $.command.run({ command: 'statusline-resets', args: bad })
    expect(answer.text).toBe(USAGE)
    expect(s.runs.length).toBe(0)
  })
}

test('non-zero exit returns trimmed stderr', async ($, on) => {
  stubs(on, { os: 'Windows_NT', answer: () => ({ exitCode: 1, stdout: '', stderr: 'resets-toggle: statusline.json is not valid JSON\n' }) })
  const answer = await $.command.run({ command: 'statusline-resets', args: 'off' })
  expect(answer.text).toBe('resets-toggle: statusline.json is not valid JSON')
})

test('non-zero exit with empty stderr names the exit code', async ($, on) => {
  stubs(on, { os: 'Windows_NT', answer: () => ({ exitCode: 2, stdout: 'ignored\n', stderr: '  \n' }) })
  const answer = await $.command.run({ command: 'statusline-resets', args: 'on' })
  expect(answer.text).toBe('claude-statusline: toggle failed (exit 2)')
})

test('a rejected process.run returns the failure text', async ($, on) => {
  stubs(on, { os: 'Windows_NT', answer: () => 'spawn pwsh ENOENT' })
  const answer = await $.command.run({ command: 'statusline-resets', args: '' })
  expect(answer.text).toMatch(/^claude-statusline: toggle failed: /)
  expect(answer.text).toContain('spawn pwsh ENOENT')
})

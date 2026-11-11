// claude-statusline mod: the immediate /statusline-resets command. It answers itself (no model turn) by
// running the resets-toggle twin script for this platform. Needs Claude Code 2.1.286 or later.
// The command name must equal RESETS_COMMAND_NAME in config/identity.env (asserted by tests/test-package.sh).

const USAGE = 'Usage: /statusline-resets [toggle|on|off|clock|countdown|status]'
const FLAGS = new Map([
  ['', ['--set', 'toggle']],
  ['toggle', ['--set', 'toggle']],
  ['on', ['--set', 'on']],
  ['off', ['--set', 'off']],
  ['clock', ['--format', 'clock']],
  ['countdown', ['--format', 'countdown']],
  ['status', ['--get']],
])

async function runToggle($, flags) {
  const argv = (await $.env.get('OS')) === 'Windows_NT'
    ? ['pwsh', '-NoProfile', '-NonInteractive', '-File', $.plugin.root + '/scripts/resets-toggle.ps1', ...flags]
    : ['bash', $.plugin.root + '/scripts/resets-toggle.sh', ...flags]
  return $.process.run(argv)
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    runToggle($, ['--sync']).catch(() => {})
    try {
      await $.command.register({
        name: 'statusline-resets',
        description: 'Toggle the 5h/7d reset times on the status line',
        argumentHint: '[toggle|on|off|clock|countdown|status]',
        immediate: true,
      })
    } catch {}
    return next(e)
  })

  on('command.run', { command: 'statusline-resets' }, async ($, e) => {
    const flags = FLAGS.get((e.args || '').trim().toLowerCase())
    if (!flags) return { text: USAGE }
    try {
      const r = await runToggle($, flags)
      if (r.exitCode === 0) return { text: r.stdout.trim() }
      return { text: r.stderr.trim() || `claude-statusline: toggle failed (exit ${r.exitCode})` }
    } catch (err) {
      return { text: 'claude-statusline: toggle failed: ' + (err && err.message ? err.message : String(err)) }
    }
  })
}

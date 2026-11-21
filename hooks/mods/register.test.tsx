import { expect, mock, test } from 'claude-code/testing'

// Stands in for Claude Code's own drawing beneath the plugin: an empty box.
const engineDraw = ($: any, e: any) => {
  const { Box } = $.ui.resolve(e)
  return <Box key="engine" />
}

const BAND = {
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: true, maxRows: 8, bodyColumns: 100 },
} as const

const PANE = {
  component: 'Pane',
  requestId: 'scratch',
  props: { title: 'Scratch', isFocused: false, bodyColumns: 100, placement: 'dock' },
} as const

for (const surface of ['terminal', 'desktop'] as const) {
  test(`workers band follows a subagent from spawn to answer (${surface})`, async ($, on) => {
    mock.clock(on, { now: 1_000 })
    on('ui.render', async ($, e) => engineDraw($, e))
    on('agent.spawn', async () => ({ model: 'haiku', agentId: 'a1' }))
    on('tool.call', async () => ({ result: 'ok' }) as never)
    on('turn.complete', async () => ({ text: '' }))

    const band = await $.ui.mount({ plugin: 'leek-skills', surface, ...BAND } as never)
    expect(await band.find({ type: 'Text', text: /Workers/ })).toBeUndefined()

    await $.agent.spawn({ prompt: 'review', description: 'review auth diff', subagentType: 'leek-skills:pr-reviewer' } as never)
    await $.tool.call({ tool: 'Bash', command: 'git diff main', tool_use_id: 't1', agentId: 'a1' } as never)
    expect(await band.find({ type: 'Text', text: /Workers 0\/1 done/ })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /review auth diff · 1 tools .*Bash: git diff main/ })).toBeDefined()

    await $.turn.complete({ agentId: 'a1', reason: 'answer', answer: '', durationMs: 5, isAborted: false, turnId: 'x' })
    expect(await band.find({ type: 'Text', text: /Workers 1\/1 done/ })).toBeDefined()

    await band.press({ key: 'hide' })
    expect(await band.find({ type: 'Text', text: /Workers/ })).toBeUndefined()
  })
}

test('main-loop tool calls are not counted as workers', async ($, on) => {
  on('ui.render', async ($, e) => engineDraw($, e))
  on('tool.call', async () => ({ result: 'ok' }) as never)
  await $.tool.call({ tool: 'Bash', command: 'ls', tool_use_id: 't1' } as never)

  const band = await $.ui.mount({ plugin: 'leek-skills', surface: 'terminal', ...BAND } as never)
  expect(await band.find({ type: 'Text', text: /Workers/ })).toBeUndefined()
})

test('/scratch draws the board and answers with a tally, or the table where no pane draws', async ($, on) => {
  const files: Record<string, string> = {
    '/repo/.scratch/auth/spec.md': '---\ntitle: Auth\nstatus: ready-for-agent\n---\n',
    '/repo/.scratch/auth/tickets/01-login.md': '---\ntitle: Login form\nstatus: ready-for-agent\nblocked-by: []\n---\n',
  }
  on('ui.render', async ($, e) => engineDraw($, e))
  mock.clock(on, { now: 0 })
  on('session.cwd', async () => ({ value: '/repo' }) as never)
  on('fs.exists', async (_$, e) => ({ value: e.path === '/repo/.scratch' }) as never)
  on('fs.read', async (_$, e) => ({ value: files[(e as { path: string }).path] ?? '' }) as never)
  on('fs.list', async (_$, e) => {
    const names = new Map<string, 'file' | 'dir'>()
    for (const full of Object.keys(files)) {
      if (!full.startsWith(`${e.path}/`)) continue
      const parts = full.slice(e.path.length + 1).split('/')
      names.set(parts[0] ?? '', parts.length > 1 ? 'dir' : 'file')
    }
    const value = [...names].map(([name, kind]) => ({ name, kind, size: 1, mtimeMs: 0, isLink: false }))
    return { value } as never
  })
  let isPlaced = true
  on('ui.open', async () => ({ value: { isPlaced } }) as never)

  const drawn = await $.command.run({ command: 'scratch', args: '' } as never)
  expect(drawn.text).toBe('1 open, 0 stale, 0 mismatched, 0 done. Commit checks: /scratch-status.')

  isPlaced = false
  const undrawn = await $.command.run({ command: 'scratch', args: '' } as never)
  expect(undrawn.text).toContain('| `auth` | open |')
  expect(undrawn.text).toContain('/implement .scratch/auth/tickets/01-login.md')

  const pane = await $.ui.mount({ plugin: 'leek-skills', surface: 'terminal', ...PANE } as never)
  expect(await pane.find({ type: 'Text', text: /01 Login form/ })).toBeDefined()
})

test('the scratch pane tags a ticket only with blockers still open', async ($, on) => {
  const files: Record<string, string> = {
    '/repo/.scratch/auth/tickets/01-login.md': '---\ntitle: Login form\nstatus: closed\n---\n',
    '/repo/.scratch/auth/tickets/02-logout.md': '---\ntitle: Logout\nstatus: ready-for-agent\n---\n',
    '/repo/.scratch/auth/tickets/03-reset.md': '---\ntitle: Reset\nstatus: ready-for-agent\nblocked-by: [01, 02]\n---\n',
    '/repo/.scratch/auth/tickets/04-audit.md': '---\ntitle: Audit\nstatus: in-progress\nblocked-by: [01]\n---\n',
  }
  on('ui.render', async ($, e) => engineDraw($, e))
  mock.clock(on, { now: 0 })
  on('session.cwd', async () => ({ value: '/repo' }) as never)
  on('fs.exists', async (_$, e) => ({ value: e.path === '/repo/.scratch' }) as never)
  on('fs.read', async (_$, e) => ({ value: files[(e as { path: string }).path] ?? '' }) as never)
  on('fs.list', async (_$, e) => {
    const names = new Map<string, 'file' | 'dir'>()
    for (const full of Object.keys(files)) {
      if (!full.startsWith(`${e.path}/`)) continue
      const parts = full.slice(e.path.length + 1).split('/')
      names.set(parts[0] ?? '', parts.length > 1 ? 'dir' : 'file')
    }
    const value = [...names].map(([name, kind]) => ({ name, kind, size: 1, mtimeMs: 0, isLink: false }))
    return { value } as never
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }) as never)

  await $.command.run({ command: 'scratch', args: '' } as never)
  const pane = await $.ui.mount({ plugin: 'leek-skills', surface: 'terminal', ...PANE } as never)
  expect(await pane.find({ type: 'Text', text: /03 Reset\s+\[blocked by 02\]$/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /04 Audit$/ })).toBeDefined()
})

test('/scratch takes a path as the slug, ages a tracked file by its last commit, and empties the pane when .scratch/ is gone', async ($, on) => {
  const DAY = 86_400_000
  const now = 100 * DAY
  const files: Record<string, string> = {
    '/repo/.scratch/auth/tickets/01-login.md': '---\ntitle: Login form\nstatus: ready-for-agent\n---\n',
    '/repo/.scratch/billing/tickets/01-invoice.md': '---\ntitle: Invoice\nstatus: ready-for-agent\n---\n',
  }
  let hasScratch = true
  on('ui.render', async ($, e) => engineDraw($, e))
  mock.clock(on, { now })
  on('session.cwd', async () => ({ value: '/repo' }) as never)
  on('fs.exists', async () => ({ value: hasScratch }) as never)
  on('fs.read', async (_$, e) => ({ value: files[(e as { path: string }).path] ?? '' }) as never)
  on('fs.list', async (_$, e) => {
    const names = new Map<string, 'file' | 'dir'>()
    for (const full of Object.keys(files)) {
      if (!full.startsWith(`${e.path}/`)) continue
      const parts = full.slice(e.path.length + 1).split('/')
      names.set(parts[0] ?? '', parts.length > 1 ? 'dir' : 'file')
    }
    // Every file was touched just now; only git knows the auth ticket is 40 days old.
    const value = [...names].map(([name, kind]) => ({ name, kind, size: 1, mtimeMs: now, isLink: false }))
    return { value } as never
  })
  on('process.run', async (_$, e) => {
    const argv = (e as { argv: readonly string[] }).argv
    const stdout =
      argv[1] === 'ls-files'
        ? '.scratch/auth/tickets/01-login.md\0'
        : argv.includes('log')
          ? `\0${(now - 40 * DAY) / 1000}\n\n.scratch/auth/tickets/01-login.md\n\0${(now - 50 * DAY) / 1000}\n\n.scratch/auth/tickets/01-login.md\n`
          : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } } as never
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }) as never)
  on('tool.call', async () => ({ result: 'ok' }) as never)

  const all = await $.command.run({ command: 'scratch', args: '' } as never)
  expect(all.text).toBe('2 open, 1 stale, 0 mismatched, 0 done. Commit checks: /scratch-status.')

  const one = await $.command.run({ command: 'scratch', args: ' .scratch/auth/ ' } as never)
  expect(one.text).toBe('1 open, 1 stale, 0 mismatched, 0 done. Commit checks: /scratch-status.')
  const pane = await $.ui.mount({ plugin: 'leek-skills', surface: 'terminal', ...PANE } as never)
  expect(await pane.find({ type: 'Text', text: /01 Login form/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /01 Invoice/ })).toBeUndefined()

  // .scratch/ is removed while the pane is open: the next rescan must not leave the old board up.
  hasScratch = false
  await $.tool.call({ tool: 'Bash', command: 'rm -r .scratch/', tool_use_id: 't1' } as never)
  expect(await pane.find({ type: 'Text', text: /01 Login form/ })).toBeUndefined()
  expect(await pane.find({ type: 'Text', text: /No efforts in \.scratch\// })).toBeDefined()
})

test('ticket_board draws each ticket beside its running implementer, or asks for chat lines where no pane draws', async ($, on) => {
  mock.clock(on, { now: 0 })
  on('ui.render', async ($, e) => engineDraw($, e))
  on('agent.spawn', async () => ({ model: 'sonnet', agentId: 'a1' }))
  on('tool.call', async () => ({ result: 'ok' }) as never)
  let isPlaced = true
  on('ui.open', async () => ({ value: { isPlaced } }) as never)

  const list = [
    { number: '01', title: 'Login form', status: 'running' },
    { number: '02', title: 'Logout', status: 'blocked', note: 'by 01' },
  ]
  const shown = await $.tool.call({ tool: 'mcp__leek-skills__ticket_board', board: 'auth', kind: 'spec', tickets: list, tool_use_id: 's1' } as never)
  expect(String((shown as { result: unknown }).result)).toContain('Skip the chat progress line')

  await $.agent.spawn({ prompt: 'build', description: 'build 01', subagentType: 'general-purpose', name: 'auth--01' } as never)
  await $.tool.call({ tool: 'Bash', command: 'php artisan test', tool_use_id: 't1', agentId: 'a1' } as never)

  const pane = await $.ui.mount({
    plugin: 'leek-skills',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'tickets',
    props: { title: 'Spec: auth', isFocused: false, bodyColumns: 120, placement: 'dock' },
  } as never)
  expect(await pane.find({ type: 'Text', text: /0 of 2 done · 1 running · 1 blocked/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /01 Login form.*running.*1 tools.*Bash: php artisan test/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /02 Logout.*blocked · by 01/ })).toBeDefined()

  isPlaced = false
  const undrawn = await $.tool.call({
    tool: 'mcp__leek-skills__ticket_board',
    board: 'auth',
    kind: 'spec',
    tickets: [{ number: '01', status: 'merged' }],
    tool_use_id: 's2',
  } as never)
  expect(String((undrawn as { result: unknown }).result)).toContain('post the progress line in chat')
})

test('ticket_board matches an unnamed worker by the first word of its description', async ($, on) => {
  mock.clock(on, { now: 0 })
  on('ui.render', async ($, e) => engineDraw($, e))
  on('agent.spawn', async () => ({ model: 'sonnet', agentId: 'a2' }))
  on('tool.call', async () => ({ result: 'ok' }) as never)
  on('ui.open', async () => ({ value: { isPlaced: true } }) as never)

  await $.tool.call({
    tool: 'mcp__leek-skills__ticket_board',
    board: 'auth',
    kind: 'spec',
    tickets: [{ number: '01', title: 'Login form', status: 'running' }],
    tool_use_id: 's1',
  } as never)
  await $.agent.spawn({ prompt: 'build', description: 'auth--01 build login', subagentType: 'general-purpose' } as never)
  await $.tool.call({ tool: 'Bash', command: 'php artisan test', tool_use_id: 't1', agentId: 'a2' } as never)

  const pane = await $.ui.mount({
    plugin: 'leek-skills',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'tickets',
    props: { title: 'Spec: auth', isFocused: false, bodyColumns: 120, placement: 'dock' },
  } as never)
  expect(await pane.find({ type: 'Text', text: /01 Login form.*running.*1 tools.*Bash: php artisan test/ })).toBeDefined()
})

test('ticket_board shows the review stage and each finding once the tickets are merged', async ($, on) => {
  mock.clock(on, { now: 0 })
  on('ui.render', async ($, e) => engineDraw($, e))
  on('tool.call', async () => ({ result: 'ok' }) as never)
  on('ui.open', async () => ({ value: { isPlaced: true } }) as never)

  const board = { tool: 'mcp__leek-skills__ticket_board', board: 'auth', kind: 'spec' }
  await $.tool.call({ ...board, tickets: [{ number: '01', title: 'Login form', status: 'merged' }], tool_use_id: 's1' } as never)
  await $.tool.call({
    ...board,
    stage: 'fix pass',
    findings: [
      { id: '1', title: 'Old workers\' runs vanish from the audit list', status: 'fixed', note: 'a1b2c3' },
      { id: '2', title: 'Notes page checks readiness once per row', status: 'fixing' },
    ],
    tool_use_id: 's2',
  } as never)

  const pane = await $.ui.mount({
    plugin: 'leek-skills',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'tickets',
    props: { title: 'Spec: auth', isFocused: false, bodyColumns: 120, placement: 'dock' },
  } as never)
  expect(await pane.find({ type: 'Text', text: /fix pass.*1 of 2 fixed · 1 fixing/ })).toBeDefined()
  // The id is a key only; the row reads as the title.
  expect(await pane.find({ type: 'Text', text: /✓ Old workers' runs vanish from the audit list {2}fixed · a1b2c3/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /◐ Notes page checks readiness once per row {2}fixing/ })).toBeDefined()
})

test('ticket_board counts not-built tickets as open and lists the work open after the run', async ($, on) => {
  mock.clock(on, { now: 0 })
  on('ui.render', async ($, e) => engineDraw($, e))
  on('tool.call', async () => ({ result: 'ok' }) as never)
  on('ui.open', async () => ({ value: { isPlaced: true } }) as never)

  const board = { tool: 'mcp__leek-skills__ticket_board', board: 'auth', kind: 'spec' }
  const pane = await $.ui.mount({
    plugin: 'leek-skills',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'tickets',
    props: { title: 'Spec: auth', isFocused: false, bodyColumns: 120, placement: 'dock' },
  } as never)

  await $.tool.call({
    ...board,
    tickets: [
      { number: '01', title: 'Login form', status: 'closed' },
      { number: '02', title: 'Logout', status: 'not-built', note: 'held for a person' },
      { number: '03', title: 'Old flow', status: 'skipped', note: 'closed in an earlier run' },
    ],
    tool_use_id: 's1',
  } as never)
  expect(await pane.find({ type: 'Text', text: /1 of 2 done · 1 not built/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /□ 02 Logout {2}not-built · held for a person/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /– 03 Old flow {2}skipped/ })).toBeDefined()
  // No open list yet: the section stays out.
  expect(await pane.find({ type: 'Text', text: /Open after this run/ })).toBeUndefined()

  const listed = await $.tool.call({
    ...board,
    open: [
      { id: 'a', title: 'Fix for the audit list is not pushed', kind: 'not-shipped', where: '#101' },
      { id: 'b', title: 'Second sign-in method', kind: 'your-decision', where: 'untracked' },
    ],
    tool_use_id: 's2',
  } as never)
  expect(String((listed as { result: unknown }).result)).toContain('2 open after this run (1 untracked)')
  // The reply hands back each unfinished entry's id and kind, which the pane never draws.
  expect(String((listed as { result: unknown }).result)).toContain(
    'Still open, by id (send done: true once one is resolved): a (not-shipped): Fix for the audit list is not pushed; b (your-decision): Second sign-in method',
  )
  const asked = await $.tool.call({ ...board, tool_use_id: 's2b' } as never)
  expect(String((asked as { result: unknown }).result)).toContain(
    'a (not-shipped): Fix for the audit list is not pushed; b (your-decision): Second sign-in method',
  )
  expect(await pane.find({ type: 'Text', text: /1 of 2 done · 1 not built · 2 open after this run \(1 untracked\)/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /^Open after this run$/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /○ Fix for the audit list is not pushed {2}not shipped · #101/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /! Second sign-in method {2}your decision · untracked/ })).toBeDefined()

  await $.tool.call({ ...board, open: [{ id: 'a', done: true }], tool_use_id: 's3' } as never)
  expect(await pane.find({ type: 'Text', text: /✓ Fix for the audit list is not pushed {2}done · #101/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /1 open after this run \(1 untracked\)/ })).toBeDefined()
})

test('ticket_board keeps the safe-to-merge stack under the header, wrapped to the pane', async ($, on) => {
  mock.clock(on, { now: 0 })
  on('ui.render', async ($, e) => engineDraw($, e))
  on('tool.call', async () => ({ result: 'ok' }) as never)
  on('ui.open', async () => ({ value: { isPlaced: true } }) as never)

  const board = { tool: 'mcp__leek-skills__ticket_board', board: 'auth', kind: 'spec' }
  const pane = await $.ui.mount({
    plugin: 'leek-skills',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'tickets',
    props: { title: 'Spec: auth', isFocused: false, bodyColumns: 34, placement: 'dock' },
  } as never)

  await $.tool.call({ ...board, tickets: [{ number: '01', title: 'Login form', status: 'merged' }], tool_use_id: 's1' } as never)
  expect(await pane.find({ type: 'Text', text: /Safe to merge/ })).toBeUndefined()

  const stack = Array.from({ length: 6 }, (_, n) => ({ number: String(6487 + n), position: n + 1, status: 'safe' }))
  await $.tool.call({
    ...board,
    stack,
    integration: { number: '6486', into: 'main', safe: false, note: 'build not finished' },
    tool_use_id: 's2',
  } as never)
  expect(await pane.find({ type: 'Text', text: /Safe to merge 6 of 6 safe/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /^ {2}#6487 → #6488 → #6489 → #6490$/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /^ {2}→ #6491 → #6492$/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /✗ integration #6486 into main not safe yet · build not finished/ })).toBeDefined()

  await $.tool.call({ ...board, integration: { number: '6486', safe: true }, tool_use_id: 's3' } as never)
  expect(await pane.find({ type: 'Text', text: /^ {2}⇒ #6486 into main$/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /not safe yet/ })).toBeUndefined()

  const conflict = await $.tool.call({ ...board, stack: [{ number: '6489', status: 'not-safe', note: 'conflicts' }], tool_use_id: 's4' } as never)
  expect(String((conflict as { result: unknown }).result)).toContain('stack 2 of 6 safe')
  expect(await pane.find({ type: 'Text', text: /^ {2}#6487 → #6488$/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /✗ #6489 not safe · conflicts/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /waiting behind it: 3 more PRs and #6486/ })).toBeDefined()
})

test('followed-up subagent resumes running state and parallel fixers render on ticket board', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  on('ui.render', async ($, e) => engineDraw($, e))
  let spawnSeq = 0
  on('agent.spawn', async () => ({ model: 'sonnet', agentId: `a${++spawnSeq}` }))
  on('tool.call', async () => ({ result: 'ok' }) as never)
  on('turn.complete', async () => ({ text: '' }))
  on('ui.open', async () => ({ value: { isPlaced: true } }) as never)

  const board = { tool: 'mcp__leek-skills__ticket_board', board: 'auth', kind: 'spec' }
  await $.tool.call({
    ...board,
    tickets: [{ number: '01', title: 'Login form', status: 'running' }],
    stage: 'fix pass 1',
    tool_use_id: 's1',
  } as never)

  await $.agent.spawn({ prompt: 'build', description: 'auth--01 build login', subagentType: 'general-purpose' } as never)
  await $.tool.call({ tool: 'Bash', command: 'test 1', tool_use_id: 't1', agentId: 'a1' } as never)
  await $.turn.complete({ agentId: 'a1', reason: 'answer', answer: '', durationMs: 5, isAborted: false, turnId: 'x1' })

  const band = await $.ui.mount({ plugin: 'leek-skills', surface: 'terminal', ...BAND } as never)
  expect(await band.find({ type: 'Text', text: /Workers 1\/1 done/ })).toBeDefined()

  // Follow-up via SendMessage reuses a1: tool.call resets outcome back to running.
  await $.tool.call({ tool: 'Bash', command: 'test 2', tool_use_id: 't2', agentId: 'a1' } as never)
  expect(await band.find({ type: 'Text', text: /Workers 0\/1 done/ })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /2 tools .*Bash: test 2/ })).toBeDefined()

  // Parallel fixers (<slug>--fix-1, <slug>--fix-2) both show on the ticket pane.
  await $.agent.spawn({ prompt: 'fix 1', description: 'auth--fix-1 fix race', subagentType: 'general-purpose' } as never)
  await $.agent.spawn({ prompt: 'fix 2', description: 'auth--fix-2 fix copy', subagentType: 'general-purpose' } as never)
  await $.tool.call({ tool: 'Edit', file_path: 'a.ts', tool_use_id: 't3', agentId: 'a2' } as never)
  await $.tool.call({ tool: 'Edit', file_path: 'b.ts', tool_use_id: 't4', agentId: 'a3' } as never)

  const pane = await $.ui.mount({
    plugin: 'leek-skills',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'tickets',
    props: { title: 'Spec: auth', isFocused: false, bodyColumns: 120, placement: 'dock' },
  } as never)
  expect(await pane.find({ type: 'Text', text: /01 Login form.*2 tools.*Bash: test 2/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /review fixes 1.*1 tools.*Edit: a\.ts/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /review fixes 2.*1 tools.*Edit: b\.ts/ })).toBeDefined()
})

test('ticket_board empty probe is read-only and never wipes a mismatched board or opens an empty pane', async ($, on) => {
  mock.clock(on, { now: 0 })
  on('ui.render', async ($, e) => engineDraw($, e))
  let opens = 0
  on('ui.open', async () => {
    opens += 1
    return { value: { isPlaced: true } } as never
  })

  const none = await $.tool.call({ tool: 'mcp__leek-skills__ticket_board', board: 'auth', kind: 'spec', tool_use_id: 'p1' } as never)
  expect(String((none as { result: unknown }).result)).toBe('No active ticket board.')
  expect(opens).toBe(0)

  await $.tool.call({
    tool: 'mcp__leek-skills__ticket_board',
    board: 'auth',
    kind: 'spec',
    tickets: [{ number: '01', title: 'Login', status: 'merged' }],
    tool_use_id: 'p2',
  } as never)
  expect(opens).toBe(1)

  // Probing a different board must not wipe auth or reopen the pane.
  const mismatch = await $.tool.call({ tool: 'mcp__leek-skills__ticket_board', board: 'billing', kind: 'spec', tool_use_id: 'p3' } as never)
  expect(String((mismatch as { result: unknown }).result)).toContain('Board billing (spec) is not active; active board is auth (spec).')
  expect(opens).toBe(1)

  // auth is still intact.
  const match = await $.tool.call({ tool: 'mcp__leek-skills__ticket_board', board: 'auth', kind: 'spec', tool_use_id: 'p4' } as never)
  expect(String((match as { result: unknown }).result)).toContain('Current board (1 of 1 done).')
  expect(opens).toBe(1)
})

test('ticket_board all-landed stack renders cleanly in pane and text fallback', async ($, on) => {
  mock.clock(on, { now: 0 })
  on('ui.render', async ($, e) => engineDraw($, e))
  let isPlaced = true
  on('ui.open', async () => ({ value: { isPlaced } }) as never)

  await $.tool.call({
    tool: 'mcp__leek-skills__ticket_board',
    board: 'auth',
    kind: 'spec',
    tickets: [{ number: '01', title: 'Login', status: 'merged' }],
    stack: [
      { number: '101', position: 1, status: 'landed' },
      { number: '102', position: 2, status: 'landed' },
    ],
    tool_use_id: 'l1',
  } as never)

  const pane = await $.ui.mount({
    plugin: 'leek-skills',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'tickets',
    props: { title: 'Spec: auth', isFocused: false, bodyColumns: 80, placement: 'dock' },
  } as never)
  expect(await pane.find({ type: 'Text', text: /Safe to merge all 2 landed/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /every PR landed/ })).toBeDefined()

  isPlaced = false
  const textReply = await $.command.run({ command: 'ticket-board', args: '' } as never)
  expect(textReply.text).toContain('Safe to merge (all 2 landed): every PR landed')
})

test('post-next observer failures do not re-run next(e) and ticket_board errors do not forward to next(e)', async ($, on) => {
  const files: Record<string, string> = {
    '/repo/.scratch/auth/tickets/01-login.md': '---\ntitle: Login\nstatus: ready-for-agent\n---\n',
  }
  let failCwd = false
  let failOpen = false
  let toolRuns = 0
  mock.clock(on, { now: 0 })
  on('ui.render', async ($, e) => engineDraw($, e))
  on('session.cwd', async () => {
    if (failCwd) throw new Error('cwd boom')
    return { value: '/repo' } as never
  })
  on('fs.exists', async (_$, e) => ({ value: e.path === '/repo/.scratch' }) as never)
  on('fs.read', async (_$, e) => ({ value: files[(e as { path: string }).path] ?? '' }) as never)
  on('fs.list', async (_$, e) => {
    const names = new Map<string, 'file' | 'dir'>()
    for (const full of Object.keys(files)) {
      if (!full.startsWith(`${e.path}/`)) continue
      const parts = full.slice(e.path.length + 1).split('/')
      names.set(parts[0] ?? '', parts.length > 1 ? 'dir' : 'file')
    }
    const value = [...names].map(([name, kind]) => ({ name, kind, size: 1, mtimeMs: 0, isLink: false }))
    return { value } as never
  })
  on('ui.open', async () => {
    if (failOpen) throw new Error('ui boom')
    return { value: { isPlaced: true } } as never
  })
  on('tool.call', async () => {
    toolRuns += 1
    return { result: 'ran-once' } as never
  })

  // Open /scratch so background refresh runs on .scratch writes, then make refresh throw post-next.
  await $.command.run({ command: 'scratch', args: '' } as never)
  failCwd = true
  const called = await $.tool.call({ tool: 'Bash', command: 'touch .scratch/auth/spec.md', tool_use_id: 't1' } as never)
  expect((called as { result: unknown }).result).toBe('ran-once')
  expect(toolRuns).toBe(1)

  // An error inside ticket_board must return { deny } instead of forwarding to next(e).
  failOpen = true
  const denied = await $.tool.call({
    tool: 'mcp__leek-skills__ticket_board',
    board: 'auth',
    kind: 'spec',
    tickets: [{ number: '01', title: 'Login', status: 'running' }],
    tool_use_id: 'tb1',
  } as never)
  expect(String((denied as { deny?: unknown }).deny)).toContain('ticket_board failed:')
  expect(toolRuns).toBe(1)
})

test('/scratch resolves repo root from subdirectories, handles truncated git log, skips background rescans when unplaced, and renders open blockers numerically', async ($, on) => {
  const DAY = 86_400_000
  const now = 100 * DAY
  const files: Record<string, string> = {
    '/repo/.scratch/auth/tickets/01-done.md': '---\ntitle: Done\nstatus: closed\n---\n',
    '/repo/.scratch/auth/tickets/9-wip.md': '---\ntitle: Unclaimed wip\nstatus: in-progress\nblocked-by: [01]\n---\n',
    '/repo/.scratch/auth/tickets/10-wait.md': '---\ntitle: Waiting\nstatus: ready-for-agent\nblocked-by: [01, 9]\n---\n',
  }
  let scans = 0
  on('ui.render', async ($, e) => engineDraw($, e))
  mock.clock(on, { now })
  on('session.cwd', async () => ({ value: '/repo/packages/web' }) as never)
  on('fs.exists', async (_$, e) => ({ value: e.path === '/repo/.scratch' }) as never)
  on('fs.read', async (_$, e) => ({ value: files[(e as { path: string }).path] ?? '' }) as never)
  on('fs.list', async (_$, e) => {
    if (e.path === '/repo/.scratch') scans += 1
    const names = new Map<string, 'file' | 'dir'>()
    for (const full of Object.keys(files)) {
      if (!full.startsWith(`${e.path}/`)) continue
      const parts = full.slice(e.path.length + 1).split('/')
      names.set(parts[0] ?? '', parts.length > 1 ? 'dir' : 'file')
    }
    const value = [...names].map(([name, kind]) => ({ name, kind, size: 1, mtimeMs: now, isLink: false }))
    return { value } as never
  })
  on('process.run', async (_$, e) => {
    const argv = (e as { argv: readonly string[] }).argv
    if (argv[1] === 'rev-parse') {
      return { value: { exitCode: 0, stdout: '/repo\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } } as never
    }
    if (argv[1] === 'ls-files') {
      return {
        value: {
          exitCode: 0,
          stdout: '.scratch/auth/tickets/01-done.md\0.scratch/auth/tickets/9-wip.md\0.scratch/auth/tickets/10-wait.md\0',
          stderr: '',
          isStdoutTruncated: false,
          isStderrTruncated: false,
        },
      } as never
    }
    if (argv.includes('-1')) {
      return {
        value: {
          exitCode: 0,
          stdout: `${(now - 40 * DAY) / 1000}\n`,
          stderr: '',
          isStdoutTruncated: false,
          isStderrTruncated: false,
        },
      } as never
    }
    // Truncated bulk git log omits the old files: fallback git log -1 must recover their 40d age.
    return { value: { exitCode: 0, stdout: '\0partial', stderr: '', isStdoutTruncated: true, isStderrTruncated: false } } as never
  })
  let isPlaced = false
  on('ui.open', async () => ({ value: { isPlaced } }) as never)
  on('tool.call', async () => ({ result: 'ok' }) as never)

  // Unplaced surface: returns table with stale flag, and does NOT arm background rescans.
  const unplaced = await $.command.run({ command: 'scratch', args: '' } as never)
  expect(unplaced.text).toContain('open (stale)')
  const scansAfterUnplaced = scans
  await $.tool.call({ tool: 'Bash', command: 'rm -rf .scratch', tool_use_id: 'w1' } as never)
  expect(scans).toBe(scansAfterUnplaced)

  // Placed surface: renders openBlockers only (9, not closed 01) and does not tag unclaimed in-progress as blocked.
  isPlaced = true
  await $.command.run({ command: 'scratch', args: '' } as never)
  const pane = await $.ui.mount({ plugin: 'leek-skills', surface: 'terminal', ...PANE } as never)
  expect(await pane.find({ type: 'Text', text: /9 Unclaimed wip$/ })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /10 Waiting {2}\[blocked by 09\]/ })).toBeDefined()
})
